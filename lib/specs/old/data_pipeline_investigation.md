# Data Pipeline Investigation - PetPro360

**Status**: 🔴 Critical - Data Loss Identified
**Created**: 2025-12-05
**Priority**: P0 - Blocking Production

---

## Problem Statement

PetPro360 (pet_resorts) production data in mbuzz shows significant data loss:

| Metric | Expected | Actual | Loss |
|--------|----------|--------|------|
| Conversions | ~440+ | 88 | ~80% missing |
| Sessions | thousands | 53 | ~99% missing |
| Events | thousands | 858 | significant |
| Event Types | multiple | 1 (add_to_cart only) | missing types |

**This indicates a critical failure in the data pipeline.**

---

## Architecture Review

### Intended Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ pet_resorts Rails App                                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Railtie auto-loads middleware                               │
│     └── config/initializers/mbuzz.rb sets API key               │
│                                                                 │
│  2. Middleware::Tracking (EVERY REQUEST)                        │
│     ├── Generates/reads visitor_id cookie                       │
│     ├── Generates/reads session_id cookie                       │
│     ├── Calls POST /sessions for NEW sessions (async)           │
│     └── Sets cookies in response                                │
│                                                                 │
│  3. Mta::Track.new(event:, order:).call                         │
│     └── Calls Mbuzz.event() → POST /events                      │
│                                                                 │
│  4. Mta::Convert.new(event:, order:).call                       │
│     └── Calls Mbuzz.conversion() → POST /conversions            │
│                                                                 │
│  5. Mta::Identify.new(user:).call                               │
│     └── Calls Mbuzz.identify() → POST /identify                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ mbuzz API (https://mbuzz.co/api/v1)                             │
├─────────────────────────────────────────────────────────────────┤
│  POST /sessions    → Sessions::CreationService                  │
│  POST /events      → Events::IngestionService                   │
│  POST /conversions → Conversions::TrackingService               │
│  POST /identify    → Identities::IdentificationService          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Investigation Areas

### 1. Middleware Not Running?

**Hypothesis**: The Railtie middleware isn't being loaded or is being bypassed.

**Evidence needed**:
- [ ] Check if `_mbuzz_vid` and `_mbuzz_sid` cookies are being set in browser
- [ ] Check pet_resorts middleware stack: `rails middleware`
- [ ] Check if Railtie is loading: add debug logging

**pet_resorts check**:
```ruby
# In rails console
Rails.application.middleware.middlewares.map(&:name).include?("Mbuzz::Middleware::Tracking")
```

### 2. Sessions Not Being Created?

**Hypothesis**: Middleware runs but `POST /sessions` fails silently.

**Evidence needed**:
- [ ] Check mbuzz production logs for session creation requests
- [ ] Check if sessions are created but with wrong account
- [ ] Verify API key is correct and not test key

**mbuzz production check**:
```ruby
# Check session creation timestamps
account = Account.find_by(name: 'PetPro360')
account.sessions.order(:created_at).pluck(:created_at, :session_id).last(10)

# Check if sessions have UTM data (indicates proper creation via POST /sessions)
account.sessions.where.not(initial_utm: nil).count
account.sessions.where(initial_utm: nil).count
```

### 3. Conversions Not Being Sent?

**Hypothesis**: `Mta::Convert` isn't being called or fails silently.

**Evidence needed**:
- [ ] Check where `Mta::Convert` is called in pet_resorts
- [ ] Verify the code path is actually executed
- [ ] Check mbuzz API logs for conversion requests

**pet_resorts locations calling Mta::Convert**:
```ruby
# app/controllers/flow/booking/reviews_controller.rb:78-79
def mta_convert
  Mta::Convert.new(event: 'estimate_accepted', order: @order).call
end
```

**Questions**:
- Is `mta_convert` only called for `estimate_accepted`?
- What about actual purchases/payments?
- Are there other conversion types that should be tracked?

### 4. API Requests Failing Silently?

**Hypothesis**: Requests are sent but fail, errors swallowed.

**Evidence needed**:
- [ ] Check mbuzz-ruby gem error handling
- [ ] Check pet_resorts logs for "Failed to send event to MTA" errors
- [ ] Verify API URL is correct (not localhost, not wrong domain)

**mbuzz-ruby gem error handling** (lib/mbuzz/api.rb):
```ruby
# Need to check: Does it log errors? Does it return false silently?
```

### 5. Wrong API Key or Environment?

**Hypothesis**: Using test key instead of live key, or wrong account.

**Evidence needed**:
- [ ] Check pet_resorts credentials for mta key
- [ ] Verify key matches PetPro360 account in mbuzz
- [ ] Check if data is going to a different account

**pet_resorts check**:
```ruby
Rails.application.credentials.dig(:mta, :key)
Rails.application.credentials.dig(:mta, :url)
```

### 6. Enabled Flag False?

**Hypothesis**: `Mbuzz.config.enabled` is false in production.

**Evidence**:
```ruby
# pet_resorts/config/initializers/mbuzz.rb
Mbuzz.config.enabled = Rails.application.credentials.dig(:mta, :key).present?
```

If credentials are missing or nil, tracking is disabled.

---

## Data Reconciliation

### What pet_resorts Should Be Sending

| Trigger | Service | Event/Conversion Type | When |
|---------|---------|----------------------|------|
| Add item to cart | `Mta::Track` | `add_to_cart` | OrderItemsController#create |
| Quote accepted | `Mta::Convert` | `estimate_accepted` | ReviewsController#update |
| User login | `Mta::Identify` | identify | EmailAuthentication concern |
| Every request | Middleware | session (if new) | Automatic |

### What's Missing

Based on 858 add_to_cart events but only 88 conversions:
- **Conversion rate**: 88/858 = 10.3%
- **Expected if 5x conversions**: 440/858 = 51% conversion rate

**This suggests**:
1. `Mta::Convert` is NOT being called for most conversions, OR
2. Conversion requests are failing, OR
3. There's another conversion point not tracked

### Questions for pet_resorts Business Logic

1. What is the full booking flow?
   - Search → Add to Cart → Review Quote → Accept Quote → Payment → Confirmation?

2. Where does money change hands?
   - Is `estimate_accepted` the actual purchase, or is there a payment step?

3. Are there other conversion points?
   - Deposit paid?
   - Full payment received?
   - Booking confirmed?

4. How many bookings have been completed in the same time period?
   - Query pet_resorts production for Order completions

---

## Immediate Actions

### 1. Production Data Audit (mbuzz)

```ruby
account = Account.find_by(name: 'PetPro360')

# Sessions analysis
puts "Total sessions: #{account.sessions.count}"
puts "Sessions with UTM: #{account.sessions.where.not(initial_utm: nil).count}"
puts "Sessions without UTM: #{account.sessions.where(initial_utm: nil).count}"
puts "Sessions by channel: #{account.sessions.group(:channel).count}"

# Events analysis
puts "Total events: #{account.events.count}"
puts "Events by type: #{account.events.group(:event_type).count}"
puts "Events with session: #{account.events.where.not(session_id: nil).count}"
puts "Events without session: #{account.events.where(session_id: nil).count}"

# Conversions analysis
puts "Total conversions: #{account.conversions.count}"
puts "Conversions by type: #{account.conversions.group(:conversion_type).count}"
puts "Conversions with revenue: #{account.conversions.where.not(revenue: nil).count}"
puts "Total revenue: #{account.conversions.sum(:revenue)}"

# Date range
puts "First event: #{account.events.minimum(:occurred_at)}"
puts "Last event: #{account.events.maximum(:occurred_at)}"
puts "First session: #{account.sessions.minimum(:started_at)}"
puts "Last session: #{account.sessions.maximum(:started_at)}"
```

### 2. Production Data Audit (pet_resorts)

```ruby
# Count actual bookings/orders in the same period
start_date = Date.new(2025, 11, 27)  # mbuzz account creation date
end_date = Date.today

# Completed orders
Order.where(created_at: start_date..end_date).where(status: 'completed').count

# Quotes accepted
Quote.where(created_at: start_date..end_date).where(status: 'accepted').count

# Compare with mbuzz conversion count
```

### 3. Check Middleware Loading (pet_resorts)

```ruby
# Rails console
Rails.application.middleware.middlewares.map(&:name)
# Should include "Mbuzz::Middleware::Tracking"
```

### 4. Check API Configuration (pet_resorts)

```ruby
# Rails console
puts "API Key present: #{Rails.application.credentials.dig(:mta, :key).present?}"
puts "API URL: #{Rails.application.credentials.dig(:mta, :url)}"
puts "Mbuzz enabled: #{Mbuzz.config.enabled}"
puts "Mbuzz API URL: #{Mbuzz.config.api_url}"
```

### 5. Test API Connection (pet_resorts)

```ruby
# Try sending a test event
Mbuzz.event("test_event", test: true)
# Check response - should return hash with success info or false
```

---

## Suspected Issues (Code Review Findings)

### Issue A: Silent Error Swallowing in Production 🔴 CRITICAL

**Location**: `mbuzz-ruby/lib/mbuzz/api.rb:92-95`

```ruby
def self.log_error(message)
  warn "[mbuzz] #{message}" if config.debug
end
```

**Problem**: Errors are ONLY logged if `debug: true`. In production:
```ruby
# pet_resorts/config/initializers/mbuzz.rb
Mbuzz.init(
  api_key: ...,
  debug: Rails.env.development?  # FALSE in production!
)
```

**Impact**: ALL API failures are completely silent in production:
- Network timeouts
- 401 authentication errors
- 422 validation errors
- 500 server errors

**We have no visibility into failures!**

### Issue B: Middleware Thread Race Condition

**Location**: `mbuzz-ruby/lib/mbuzz/middleware/tracking.rb:86-88`

```ruby
def create_session_async
  Thread.new { create_session }
end
```

**Problem**: Fire-and-forget thread:
- Thread might not complete before process ends
- Errors in thread are lost (no logging, no retry)
- Puma workers may kill threads on request completion

**Impact**: Session creation is unreliable.

### Issue C: visitor_id May Be Nil for Conversions 🔴 CRITICAL

**Location**: `mbuzz-ruby/lib/mbuzz.rb:113-119`

```ruby
def self.conversion(conversion_type, revenue: nil, **properties)
  Client.conversion(
    visitor_id: visitor_id,  # <-- Can be nil!
    ...
  )
end

def self.visitor_id
  RequestContext.current&.request&.env&.dig(ENV_VISITOR_ID_KEY)
end
```

**Validation in ConversionRequest** (`client/conversion_request.rb:27-29`):
```ruby
def has_identifier?
  present?(@event_id) || present?(@visitor_id)  # BOTH can be nil!
end
```

**If visitor_id is nil AND event_id is nil → Conversion is silently dropped!**

**When visitor_id could be nil**:
1. First request before middleware runs
2. Background job context
3. Websocket context
4. Any non-HTTP request context

### Issue D: Missing Conversion Points in pet_resorts

`Mta::Convert` is only called in ONE place:

```ruby
# app/controllers/flow/booking/reviews_controller.rb:78-79
def mta_convert
  Mta::Convert.new(event: 'estimate_accepted', order: @order).call
end
```

**Questions**:
- What happens AFTER estimate_accepted?
- Is there a payment step?
- Is there a booking confirmation step?
- Are there other conversion types (deposit, full payment)?

### Issue E: Event Properties Include Revenue (Confusing Data)

**Location**: `pet_resorts/app/services/mta/track.rb:6`

```ruby
def run
  Mbuzz.event(event, revenue: revenue, location: location)
end
```

**Problem**: Events are being sent with `revenue` in properties.

**Evidence from production**:
```ruby
account.events.last.properties
# => {"url" => "...", "revenue" => 334.0, "location" => "..."}
```

This is confusing because:
- Events shouldn't have revenue (conversions should)
- This suggests add_to_cart events have order total, not item price
- Makes data analysis confusing

---

## Fix Plan (After Investigation)

### Phase 1: Diagnose
1. Run production audits on both systems
2. Verify middleware is loading
3. Verify API connectivity
4. Check for error logs

### Phase 2: Fix Data Pipeline
1. Fix any middleware/thread issues
2. Add missing conversion tracking points
3. Add logging/monitoring for failed requests

### Phase 3: Fix Funnel Display
1. Update `FunnelStagesQuery` to include sessions as "Visits"
2. Include conversions as final funnel stage
3. Test with real data

---

## Most Likely Root Causes (Ranked)

### 1. 🔴 Silent Failures Due to No Debug Logging (HIGH CONFIDENCE)

With `debug: false` in production, we have ZERO visibility. Requests could be:
- Timing out
- Getting 401 (bad API key)
- Getting 422 (validation errors)
- Failing silently

**Immediate fix**: Enable debug logging in pet_resorts production temporarily.

### 2. 🔴 visitor_id is Nil When Conversions Called (HIGH CONFIDENCE)

If middleware hasn't run yet, or context is lost, conversions silently fail validation.

**Test**: Add logging to see what visitor_id is when Mta::Convert is called.

### 3. 🟡 Thread Race Condition for Sessions (MEDIUM CONFIDENCE)

53 sessions for 858 events is suspicious. Sessions might be created but:
- Thread dies before completing
- Network timeout in thread
- Thread errors swallowed

### 4. 🟡 Missing Conversion Points (MEDIUM CONFIDENCE)

If `estimate_accepted` isn't the only conversion event, we're missing data.

**Verify**: What percentage of orders have `estimate_accepted` vs other completion states?

---

## Immediate Diagnostic Commands

### pet_resorts Production Console

```ruby
# 1. Check middleware is loaded
puts Rails.application.middleware.middlewares.map(&:name).grep(/mbuzz/i)

# 2. Check configuration
puts "API Key: #{Rails.application.credentials.dig(:mta, :key)&.first(20)}..."
puts "API URL: #{Rails.application.credentials.dig(:mta, :url)}"
puts "Enabled: #{Mbuzz.config.enabled}"

# 3. Test API connectivity (will show errors in console)
Mbuzz.config.debug = true  # TEMPORARY
result = Mbuzz.event("diagnostic_test", diagnostic: true)
puts "Event result: #{result.inspect}"

# 4. Check order counts for comparison
start_date = Date.new(2025, 11, 27)
puts "Orders created: #{Order.where('created_at >= ?', start_date).count}"
puts "Orders completed: #{Order.where('created_at >= ?', start_date).where(status: 'completed').count}"
puts "Quotes accepted: #{Quote.where('created_at >= ?', start_date).where(status: 'accepted').count}"
```

### mbuzz Production Console

```ruby
account = Account.find_by(name: 'PetPro360')

# Full audit
{
  sessions: account.sessions.count,
  sessions_with_utm: account.sessions.where.not(initial_utm: nil).count,
  sessions_by_channel: account.sessions.group(:channel).count,
  events: account.events.count,
  events_by_type: account.events.group(:event_type).count,
  conversions: account.conversions.count,
  conversions_by_type: account.conversions.group(:conversion_type).count,
  total_revenue: account.conversions.sum(:revenue),
  date_range: {
    first_event: account.events.minimum(:occurred_at),
    last_event: account.events.maximum(:occurred_at)
  }
}
```

---

## Next Steps

1. **User to run**: pet_resorts diagnostic commands above
2. **User to run**: mbuzz production audit above
3. **Compare**: Order counts in pet_resorts vs conversions in mbuzz
4. **Enable**: Temporary debug logging to catch errors
5. **Then**: Implement fixes based on findings

---

## Related Fixes Needed (After Investigation)

### mbuzz-ruby Gem Fixes
1. Always log errors (not just in debug mode) - at minimum to Rails.logger
2. Replace Thread.new with proper async (ActiveJob or similar)
3. Add instrumentation/callbacks for monitoring

### pet_resorts Fixes
1. Verify all conversion points are tracked
2. Add error handling/logging to Mta services
3. Verify middleware is running

### mbuzz Server Fixes
1. Fix FunnelStagesQuery to include sessions as "Visits"
2. Add API request logging for debugging
3. Add monitoring/alerts for data pipeline health
