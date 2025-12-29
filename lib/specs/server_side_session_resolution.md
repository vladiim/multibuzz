# Server-Side Session Resolution

## Problem

The current middleware (mbuzz-ruby) generates session IDs using fixed 30-minute time buckets from epoch:

```ruby
time_bucket = timestamp / SESSION_TIMEOUT_SECONDS  # e.g., timestamp / 1800
session_id = hash(visitor_id + time_bucket)
```

This causes edge cases where users arriving near bucket boundaries get "short" sessions. For example, a user arriving at minute 29 of a bucket only gets 1 minute before their session ID changes.

## Solution

Move session resolution entirely to the API backend. The middleware becomes a thin pass-through that sends `visitor_id`, `ip`, `user_agent`, etc. The API resolves the correct session based on actual activity history (true sliding window).

---

## Architecture Changes

### Before

```
Client → Middleware (generates session_id) → API (receives session_id)
```

### After

```
Client → Middleware (sends visitor_id, ip, user_agent) → API (resolves session_id in background job)
```

---

## Implementation

### 1. Database Migration

Add `last_activity_at` and `device_fingerprint` columns to sessions table:

```ruby
# db/migrate/XXXXXX_add_session_resolution_columns.rb

class AddSessionResolutionColumns < ActiveRecord::Migration[8.0]
  def change
    add_column :sessions, :last_activity_at, :datetime
    add_column :sessions, :device_fingerprint, :string  # SHA256 of ip|user_agent

    add_index :sessions, [:visitor_id, :device_fingerprint, :last_activity_at],
              name: "index_sessions_for_resolution"

    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE sessions SET last_activity_at = started_at WHERE last_activity_at IS NULL
        SQL
      end
    end
  end
end
```

**Why device_fingerprint?** Same visitor on different devices = different sessions.
A visitor on their laptop and phone should have separate sessions even within the 30-minute window.

### 2. Sessions::ResolutionService

**File:** `app/services/sessions/resolution_service.rb`

**Purpose:** Resolve the correct session_id for an incoming event based on activity history.

**Constants:**
- `SESSION_TIMEOUT = 30.minutes` - Window for session continuation
- `RACE_WINDOW = 5.minutes` - Dedup window for concurrent request deterministic ID

**Inputs:**
- `account` - Current account (for multi-tenancy scoping)
- `visitor_id` - The visitor's external ID (e.g., "vis_abc123")
- `ip` - Request IP address (anonymized)
- `user_agent` - Request user agent string

**Algorithm:**
1. Compute `device_fingerprint = SHA256(ip|user_agent)[0:32]`
2. Find visitor record by `visitor_id`
3. If visitor not found → generate deterministic ID (new visitor)
4. Query for active session:
   - `visitor_id` matches
   - `device_fingerprint` matches (same device)
   - `ended_at` is NULL
   - `last_activity_at` > 30 minutes ago
5. If session found → return `session.session_id` (continue session)
6. If no session → generate deterministic ID (new session)

**Deterministic ID generation:**
```
time_bucket = current_time / 5.minutes
session_id = SHA256(visitor_id + device_fingerprint + time_bucket)[0:32]
```

This ensures concurrent requests within a 5-minute window get the same session_id, preventing race condition duplicates.

**Pattern:** Plain Ruby class with `initialize` + `call`. Does NOT inherit from ApplicationService (returns string, not success/error hash).

### 3. Update Sessions::TrackingService

**File:** `app/services/sessions/tracking_service.rb`

**Changes required:**
- Add `device_fingerprint` parameter to initializer
- Store `device_fingerprint` when creating new sessions
- Set `last_activity_at` to event timestamp on session creation
- Update `last_activity_at` to current time on every call (new or existing session)

**Pattern:** Follows existing `ApplicationService` pattern with `initialize` + private `run` method.

### 4. Update Activity Tracking Services

All services that interact with sessions must update `last_activity_at`:

| Service | File | Change |
|---------|------|--------|
| Sessions::TrackingService | `app/services/sessions/tracking_service.rb` | Set on create, update on every call |
| Conversions::TrackingService | `app/services/conversions/tracking_service.rb` | Update `last_activity_at` when conversion tracked |
| Identities::IdentificationService | `app/services/identities/identification_service.rb` | Update `last_activity_at` when identity linked |

### 5. Modify Events Controller

**File:** `app/controllers/api/v1/events_controller.rb`

**Changes required:**
- Capture `request.remote_ip` and `request.user_agent` from HTTP request
- Pass IP (anonymized) and user_agent in event_data to background job
- Ignore any `session_id` sent by client (backwards compatibility - accept but don't use)
- Return 202 Accepted immediately, session resolution happens in background

**Data flow:**
```
HTTP Request → Controller extracts ip + user_agent → Background Job → ResolutionService
```

### 6. Modify Processing Job

**File:** `app/jobs/events/processing_job.rb`

**Changes required:**
- Call `Sessions::ResolutionService` with visitor_id, ip, user_agent
- Compute `device_fingerprint` from ip + user_agent
- Pass resolved `session_id` and `device_fingerprint` to downstream services
- Pass `device_fingerprint` to `Sessions::TrackingService` for storage

**Pattern:** Thin job wrapper - delegates to services for business logic.

### 7. SDK Data Requirements

**The SDKs do NOT need to send ip/user_agent explicitly.** The API captures these from HTTP request headers:

| Data | Source | Notes |
|------|--------|-------|
| `ip` | `request.remote_ip` | Anonymized before storage (zero last octet) |
| `user_agent` | `request.user_agent` | From `User-Agent` header |
| `visitor_id` | SDK cookie (`_mbuzz_vid`) | Existing behavior |

**SDK changes needed (future PR):**
- Remove session_id generation logic
- Remove `_mbuzz_sid` cookie handling
- Stop sending `session_id` in API requests

For now, SDKs continue generating session_ids but the API ignores them.

---

## Race Condition Handling

### The Problem

When Turbo frames or SPA prefetching makes concurrent requests:

1. Request A hits API
2. Request B hits API (same millisecond)
3. Both get queued as background jobs
4. Job A runs: no recent session → generates new ID
5. Job B runs: no recent session → generates new ID
6. Result: 2 different sessions for same visit

### The Solution

Use deterministic session ID generation for new sessions:

```ruby
fingerprint = SHA256(visitor_id + ip + user_agent)
time_bucket = current_time / 5.minutes
session_id = SHA256(fingerprint + time_bucket)[0..31]
```

**Key insight:** The 5-minute bucket is only for deduping concurrent requests, NOT for defining session boundaries. Session boundaries are determined by the 30-minute `last_activity_at` check.

### Example Flow

```
T=0:00 - Request A arrives (new visitor)
T=0:00 - Request B arrives (same visitor, Turbo frame)
T=0:00 - Request C arrives (same visitor, Turbo frame)

All three:
1. Query for session with last_activity_at > 30.minutes.ago
2. Find nothing (new visitor)
3. Generate deterministic ID: SHA256("vis_abc|192.168.1.1|Chrome" + "12345")
4. All three get: "a1b2c3d4e5f6..."

Result: All 3 events reference same session
```

---

## Session Continuation Logic

```
When event arrives:
  1. Compute device_fingerprint = SHA256(ip|user_agent)[0:32]
  2. Find visitor by visitor_id
  3. If visitor not found:
     → Generate deterministic session_id (new visitor)
  4. If visitor found:
     a. Query: sessions WHERE visitor_id = X
                       AND device_fingerprint = Y  ← Same device only!
                       AND ended_at IS NULL
                       AND last_activity_at > 30.minutes.ago
                       ORDER BY last_activity_at DESC
                       LIMIT 1
     b. If session found:
        → Return session.session_id (continue session)
     c. If no session:
        → Generate deterministic session_id (new session for this device)
```

---

## Files to Modify

### multibuzz (API Backend)

| File | Change |
|------|--------|
| `db/migrate/XXX_add_session_resolution_columns.rb` | Create - add `last_activity_at` + `device_fingerprint` columns |
| `app/models/session.rb` | No change - columns auto-available |
| `app/services/sessions/resolution_service.rb` | Create - new service |
| `app/services/sessions/tracking_service.rb` | Update - accept `device_fingerprint`, set both columns |
| `app/services/conversions/tracking_service.rb` | Update - set `last_activity_at` |
| `app/services/identities/identification_service.rb` | Update - set `last_activity_at` |
| `app/controllers/api/v1/events_controller.rb` | Update - capture ip/user_agent, ignore client session_id |
| `app/jobs/events/processing_job.rb` | Update - call ResolutionService, pass device_fingerprint |
| `app/services/sessions/identification_service.rb` | Deprecate - no longer needed for session_id |

### mbuzz-ruby (Middleware Gem) - Separate PR

| File | Change |
|------|--------|
| `lib/mbuzz/session/id_generator.rb` | Delete |
| `lib/mbuzz/middleware/tracking.rb` | Update - remove session_id generation, remove _mbuzz_sid cookie |
| `lib/mbuzz/client.rb` | Update - don't send session_id in API calls |

---

## API Contract Changes

### Before: Event Request

```json
{
  "events": [{
    "event_type": "pageview",
    "visitor_id": "vis_abc123",
    "session_id": "sess_xyz789",
    "properties": { "url": "..." }
  }]
}
```

### After: Event Request

```json
{
  "events": [{
    "event_type": "pageview",
    "visitor_id": "vis_abc123",
    "properties": { "url": "..." }
  }]
}
```

Note: `session_id` is no longer sent by client. It's resolved server-side.

### Response (unchanged structure)

```json
{
  "status": 202,
  "accepted": 1,
  "visitor_id": "vis_abc123"
}
```

---

## Migration Path

### Phase 1: API Changes (Backwards Compatible)

1. Add `last_activity_at` column to sessions
2. Create `Sessions::ResolutionService`
3. Update tracking services to set `last_activity_at`
4. Modify API to use resolution service when `session_id` is NOT provided
5. Keep existing logic when `session_id` IS provided (backwards compat)

### Phase 2: Middleware Changes

1. Update mbuzz-ruby gem to stop sending `session_id`
2. Remove `_mbuzz_sid` cookie handling
3. Remove `Sessions::IdGenerator`

### Phase 3: Cleanup

1. Remove backwards compatibility code from API
2. Deprecate `Sessions::IdentificationService` (or repurpose)

---

## Configuration

```ruby
# config/initializers/session_resolution.rb

Mbuzz.configure do |config|
  config.session_timeout = 30.minutes      # When to start new session
  config.race_dedup_window = 5.minutes     # Window for concurrent request dedup
end
```

---

## Testing Checklist

### Unit Tests

- [ ] ResolutionService returns existing session when last_activity_at < 30 min
- [ ] ResolutionService generates new ID when last_activity_at > 30 min
- [ ] ResolutionService generates new ID for new visitor
- [ ] ResolutionService generates same ID for concurrent requests (same time bucket)
- [ ] ResolutionService generates different ID after 5 min window
- [ ] ResolutionService scopes to account (no cross-account leakage)
- [ ] TrackingService updates last_activity_at
- [ ] ConversionsService updates last_activity_at
- [ ] IdentificationService updates last_activity_at

### Integration Tests

- [ ] 10 concurrent requests from same visitor → same session_id
- [ ] Request at T, request at T+10min → same session (activity updated)
- [ ] Request at T, request at T+45min → different session
- [ ] New visitor flow → generates session, subsequent requests continue it

### Load Tests

- [ ] Verify session resolution query is fast with index
- [ ] Verify deterministic ID generation doesn't bottleneck

---

## Rollback Plan

If issues arise:

1. Revert API to require `session_id` in requests
2. Redeploy previous version of mbuzz-ruby gem
3. Sessions will work as before (client-generated IDs)

The `last_activity_at` column can remain - it's additive and doesn't break existing functionality.

---

## SDK Note

> **TODO (Future PR):** The mbuzz-ruby and mbuzz-js SDKs currently still generate session IDs.
> For now, the API will **ignore** any `session_id` sent by clients and resolve sessions server-side.
> Once this feature is stable, update the SDKs to:
> 1. Remove `Sessions::IdGenerator` / session ID generation logic
> 2. Remove `_mbuzz_sid` cookie handling
> 3. Stop sending `session_id` in API requests
>
> This is a separate PR after server-side resolution is proven in production.

### Server-Side SDK Changes Required

**Issue:** Server-side SDKs (Ruby, Python, PHP) make HTTP requests from the web server to the API. The API captures `request.ip` and `request.user_agent` from these requests, but these reflect the SERVER's IP and HTTP client library (e.g., "Faraday/1.0"), not the end user's browser.

**Current Behavior:** When ip/user_agent don't match a real browser fingerprint, the API falls back to client-side `session_id`. This means server-side SDKs continue using the old time-bucket session resolution until updated.

**Required Changes (Future PR):**

| SDK | Repo | Changes |
|-----|------|---------|
| mbuzz-ruby | `mbuzz-ruby` | Forward `request.ip` and `request.user_agent` in event payload |
| mbuzz-python | `mbuzz-python` | Forward client IP and User-Agent from WSGI/ASGI request |
| mbuzz-php | `mbuzz-php` | Forward `$_SERVER['REMOTE_ADDR']` and `$_SERVER['HTTP_USER_AGENT']` |

**Example (Ruby):**
```ruby
# Current - server's request context is lost
Mbuzz::Client.track(visitor_id: vid, event_type: "page_view", properties: {})

# Updated - forward original client context
Mbuzz::Client.track(
  visitor_id: vid,
  event_type: "page_view",
  ip: request.ip,
  user_agent: request.user_agent,
  properties: {}
)
```

**Note:** JavaScript SDK (browser) works automatically since the browser sends User-Agent header directly to the API.

---

## Implementation Checklist

### Phase 1: Database Migration
- [x] Create migration `add_session_resolution_columns`
  - [x] Add `last_activity_at` datetime column
  - [x] Add `device_fingerprint` string column (SHA256 hash of ip|user_agent)
  - [x] Add composite index `[:visitor_id, :device_fingerprint, :last_activity_at]`
  - [x] Backfill existing sessions with `started_at` value
- [x] Run migration and verify

### Phase 2: Sessions::ResolutionService (TDD)
- [x] Write unit tests for `Sessions::ResolutionService`
  - [x] Test: returns existing session_id when `last_activity_at < 30.minutes.ago`
  - [x] Test: generates new ID when `last_activity_at > 30.minutes.ago`
  - [x] Test: generates new ID for unknown visitor
  - [x] Test: generates deterministic ID (same inputs → same output within 5min window)
  - [x] Test: generates different ID after 5min window passes
  - [x] Test: same visitor, different device → different session
  - [x] Test: scoped to account (no cross-account leakage)
- [x] Implement `Sessions::ResolutionService`
- [x] All tests pass (12 tests)

### Phase 3: Update Activity Tracking (TDD)
- [x] Write tests for `Sessions::TrackingService` updating `last_activity_at`
- [x] Update `Sessions::TrackingService` to set `last_activity_at`
- [x] Add `device_fingerprint` parameter to `Sessions::TrackingService`
- [x] Write tests for `Conversions::TrackingService` updating `last_activity_at`
- [x] Update `Conversions::TrackingService` to set `last_activity_at`
- [x] Write tests for `Identities::IdentificationService` updating `last_activity_at`
- [x] Update `Identities::IdentificationService` to set `last_activity_at`
- [x] All tests pass (353 service tests)

### Phase 4: Processing Service Updates (TDD)
- [x] Write tests for `Events::ProcessingService` with session resolution
- [x] Update `Events::ProcessingService` to call `Sessions::ResolutionService`
- [x] Update `Events::EnrichmentService` to add ip/user_agent to event_data
- [x] All tests pass (18 tests)

### Phase 5: Events Controller Updates (TDD)
- [x] Write integration tests for events endpoint without `session_id`
- [x] `Api::V1::EventsController` already captures ip/user_agent via EnrichmentService
- [x] Backwards compatibility: API accepts client `session_id` but resolves server-side when ip/user_agent present
- [x] All tests pass (27 controller tests)

### Phase 6: Integration Testing
- [x] Test concurrent requests → same session
- [x] Test session continuation within 30min window
- [x] Test new session after 30min gap (expired session test)
- [x] Test new visitor flow end-to-end (device fingerprint test)

### Phase 7: Cleanup & Documentation
- [ ] Update API documentation
- [ ] Remove/deprecate `Sessions::IdentificationService` if no longer needed
- [ ] Final test suite run
- [ ] Deploy to production

---

## Progress Log

| Date | Step | Status | Notes |
|------|------|--------|-------|
| 2024-12-29 | Phase 1: Migration | Complete | Added `last_activity_at` and `device_fingerprint` columns |
| 2024-12-29 | Phase 2: ResolutionService | Complete | 12 tests, TDD approach |
| 2024-12-29 | Phase 3: TrackingService | Complete | All 3 services now update `last_activity_at` |
| 2024-12-29 | Phase 4: ProcessingService | Complete | 18 tests, server-side resolution integrated |
| 2024-12-30 | Phase 5: Events Controller | Complete | 27 controller tests, integration tests added |
| 2024-12-30 | Phase 6: Integration Testing | Complete | All integration scenarios tested |
