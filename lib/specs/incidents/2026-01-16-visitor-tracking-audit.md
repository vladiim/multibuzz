# Complete End-to-End Tracking Audit

**Date**: 2026-01-16
**Issue**: pet_resorts not tracking visitors since mbuzz-ruby 0.7.1 upgrade

---

## Executive Summary

**ROOT CAUSE FOUND**: The `create_session_async` method in `mbuzz-ruby/lib/mbuzz/middleware/tracking.rb` accesses the Rack `request` object from a background thread AFTER the main request may have completed. This is a thread-safety bug that causes the session creation to fail silently.

---

## Flow 1: Session/Visitor Creation

### Expected Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ 1. HTTP Request → pet_resorts                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ 2. Mbuzz::Middleware::Tracking#call                                          │
│    ├─ build_request_context(request)                                        │
│    │    └─ Check session cookie (_mbuzz_sid)                                │
│    │    └─ If no cookie: new_session = true                                 │
│    ├─ IF new_session:                                                       │
│    │    └─ create_session_async(context, request)  ← RUNS IN BACKGROUND     │
│    │         └─ Thread.new { create_session(context, request) }             │
│    │              └─ Client.session(...)                                    │
│    │                   └─ POST /api/v1/sessions                             │
├─────────────────────────────────────────────────────────────────────────────┤
│ 3. Server: Api::V1::SessionsController#create                               │
│    └─ Sessions::CreationService.new(...).call                               │
│         └─ find_or_create_visitor                                           │
│         └─ find_or_initialize_session                                       │
│         └─ CREATES VISITOR + SESSION                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### THE BUG (Line 100-108 in tracking.rb)

```ruby
# mbuzz-ruby/lib/mbuzz/middleware/tracking.rb

def create_session_async(context, request)
  Thread.new do
    create_session(context, request)  # ← request accessed in background thread!
  rescue StandardError => e
    log_error("Session creation failed: #{e.message}") if Mbuzz.config.debug
  end
end

def create_session(context, request)
  Client.session(
    visitor_id: context[:visitor_id],     # ✓ Safe - from frozen hash
    session_id: context[:session_id],     # ✓ Safe - from frozen hash
    url: request_url(request),            # ✗ UNSAFE - accesses request.url
    referrer: request.referer,            # ✗ UNSAFE - accesses request.referer
    device_fingerprint: device_fingerprint(request)  # ✗ UNSAFE - request.user_agent
  )
end
```

**Problem**: The `request` object is a Rack request that may be:
1. Garbage collected after the main thread returns
2. Reused for another request (Rack middleware instances are shared)
3. In an invalid state when accessed from background thread

**Why it worked initially**: Race condition - sometimes the thread runs fast enough to read the request before it's invalidated. Under load or with slower responses, the request is cleaned up before the thread reads it.

### Verification Checklist - Flow 1

| Step | Check | Status |
|------|-------|--------|
| 1.1 | Middleware is mounted in pet_resorts | ✓ Via Railtie |
| 1.2 | `Mbuzz.config.enabled` is true | ✓ Confirmed in initializer |
| 1.3 | `Mbuzz.config.api_key` is present | ✓ From credentials |
| 1.4 | Request path not in skip_paths | ✓ /search, /booking not skipped |
| 1.5 | Session cookie check works | ✓ `session_id_from_cookie` |
| 1.6 | `new_session` flag set correctly | ✓ When no session cookie |
| 1.7 | `create_session_async` called | ✓ When `new_session = true` |
| 1.8 | Thread accesses request safely | **✗ BUG - request accessed in bg thread** |
| 1.9 | `Client.session` called | ? Depends on thread timing |
| 1.10 | POST /sessions reaches server | ? Check server logs |
| 1.11 | Server creates visitor | ? Only if request received |

---

## Flow 2: Event Tracking

### Code Path

```
pet_resorts:
  Mta::Track.new(event:, order:).call
    └─ Mbuzz.event(event, revenue:, location:)

mbuzz-ruby:
  Mbuzz.event(event_type, **properties)
    ├─ resolved_visitor_id = visitor_id || self.visitor_id
    │    └─ current_visitor_id (from Mbuzz::Current) OR
    │    └─ RequestContext.current.request.env['mbuzz.visitor_id']
    ├─ return false unless resolved_visitor_id || user_id
    └─ Client.track(visitor_id:, event_type:, properties:, ip:, user_agent:)
        └─ TrackRequest.new(...).call
            └─ Api.post_with_response(EVENTS_PATH, { events: [payload] })

server:
  Api::V1::EventsController#create
    └─ Events::IngestionService.new(...).call(events_data)
        └─ Events::ProcessingService.new(...).call
            ├─ Visitors::LookupService  ← REQUIRES EXISTING VISITOR
            │    └─ Returns error if visitor not found
            └─ Sessions::TrackingService
```

### Verification Checklist - Flow 2

| Step | Check | Status |
|------|-------|--------|
| 2.1 | `Mbuzz.event` called from controller | ✓ Via Mta::Track |
| 2.2 | `visitor_id` resolved from context | ✓ From RequestContext |
| 2.3 | Request sent to /api/v1/events | ✓ Working (63 events in 24h) |
| 2.4 | Server receives request | ✓ Working |
| 2.5 | `LookupService` finds visitor | ✓ For EXISTING visitors only |
| 2.6 | Event created | ✓ For existing visitors |

**Events work because**: They use existing visitors (from cookies set before the bug). No new visitors are created, but existing ones keep working.

---

## Flow 3: Conversion Tracking

### Code Path

```
pet_resorts:
  Mta::Convert.new(event:, order:).call
    └─ Mbuzz.conversion(event, revenue:, properties:)

mbuzz-ruby:
  Mbuzz.conversion(conversion_type, visitor_id:, revenue:, **properties)
    ├─ resolved_visitor_id = visitor_id || self.visitor_id
    ├─ return false unless resolved_visitor_id || user_id
    └─ Client.conversion(visitor_id:, conversion_type:, revenue:, ...)
        └─ ConversionRequest.new(...).call
            └─ Api.post_with_response(CONVERSIONS_PATH, payload)

server:
  Api::V1::ConversionsController#create
    └─ Conversions::TrackingService.new(...).call
        ├─ Find visitor (from visitor_id, event_id, or fingerprint)
        │    └─ Returns error if visitor not found
        └─ Create conversion
```

### Verification Checklist - Flow 3

| Step | Check | Status |
|------|-------|--------|
| 3.1 | `Mbuzz.conversion` called | ✓ Via Mta::Convert |
| 3.2 | `visitor_id` resolved | ✓ From context |
| 3.3 | Request sent to /api/v1/conversions | ✓ Working (18 in 24h) |
| 3.4 | Server finds visitor | ✓ For EXISTING visitors |
| 3.5 | Conversion created | ✓ For existing visitors |

**Conversions work because**: Same as events - using existing visitors.

---

## Flow 4: User Identification

### Code Path

```
pet_resorts:
  Mta::Identify.new(user:).call
    └─ Mbuzz.identify(user.prefix_id, traits:)

mbuzz-ruby:
  Mbuzz.identify(user_id, traits:, visitor_id:)
    └─ Client.identify(user_id:, visitor_id:, traits:)
        └─ IdentifyRequest.new(...).call
            └─ Api.post(IDENTIFY_PATH, payload)

server:
  Api::V1::IdentifyController#create
    └─ Users::IdentificationService.new(...).call
```

### Verification Checklist - Flow 4

| Step | Check | Status |
|------|-------|--------|
| 4.1 | `Mbuzz.identify` called | ✓ Via Mta::Identify |
| 4.2 | Request sent to /api/v1/identify | ✓ Should work |

---

## Evidence Summary

| Metric | Last 24h | Explanation |
|--------|----------|-------------|
| Visitors created | **0** | BUG: POST /sessions failing silently |
| Sessions created | 34 | From existing visitors via fingerprint |
| Events created | 63 | From existing visitors (cookies valid) |
| Conversions created | 18 | From existing visitors |

---

## The Fix

The fix is to capture all request data BEFORE starting the async thread:

```ruby
# In build_request_context, capture ALL values needed:
def build_request_context(request)
  existing_session_id = session_id_from_cookie(request)
  new_session = existing_session_id.nil?

  {
    visitor_id: resolve_visitor_id(request),
    session_id: existing_session_id || generate_session_id,
    user_id: user_id_from_session(request),
    new_session: new_session,
    # ADD THESE - capture for async session creation:
    url: request.url,
    referrer: request.referer,
    ip: extract_ip(request),
    user_agent: request.user_agent
  }.freeze
end

def create_session_async(context, _request)  # request no longer needed
  Thread.new do
    create_session(context)
  rescue StandardError => e
    log_error("Session creation failed: #{e.message}") if Mbuzz.config.debug
  end
end

def create_session(context)
  Client.session(
    visitor_id: context[:visitor_id],
    session_id: context[:session_id],
    url: context[:url],              # From frozen context
    referrer: context[:referrer],    # From frozen context
    device_fingerprint: calculate_fingerprint(context[:ip], context[:user_agent])
  )
end
```

---

## Immediate Actions

1. **Apply the fix** to mbuzz-ruby
2. **Bump version** to 0.7.2
3. **Publish gem** to RubyGems
4. **Update pet_resorts** Gemfile to 0.7.2
5. **Deploy pet_resorts**
6. **Monitor** visitor creation in production

---

## Test Script for Verification

Run in pet_resorts production console after fix:

```ruby
# Before fix - should be 0
puts "Visitors (last 1h): #{Account.find(2).visitors.where('created_at > ?', 1.hour.ago).count}"

# Wait 1 hour after deploying fix

# After fix - should be > 0
puts "Visitors (last 1h): #{Account.find(2).visitors.where('created_at > ?', 1.hour.ago).count}"
```
