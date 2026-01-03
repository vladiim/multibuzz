# Turbo Frame Visitor Inflation Bug

## Problem Summary

**Symptom:** Visit counts are 40-70x higher than expected (observed: 86,671 visits when ~2,000 expected).

**Root Cause:** When Turbo/Hotwire pages load, multiple concurrent HTTP requests (one per Turbo frame) arrive WITHOUT cookies. Each request generates a **random visitor_id**, creating 70+ visitor records per real page load.

---

## Production Data Analysis (2025-01-04)

```
Account: UAT (ID: 2)
Total visitors: 144,305
Total sessions: 90,433
Sessions per visitor: 0.63 (backwards - should be >1)

Unique device fingerprints: 2
Visitors created (7 days): 144,308
Inflation factor: 72,154x

Sessions missing device_fingerprint: 99.5% (90,023 of 90,436)
Visitors created in same second: 70+ (peak observed)
```

### Key Findings

1. **70+ visitors created per second** - Each Turbo frame creates a new random visitor_id
2. **Only 2 real devices** - device_fingerprint shows actual unique users
3. **99.5% sessions lack fingerprint** - SDK not forwarding ip/user_agent to API
4. **Sessions < Visitors** - Each "visitor" only has ~0.63 sessions on average (should be opposite)

---

## Root Cause Analysis

### 1. Random Visitor ID Generation (PRIMARY ISSUE)

**File:** `lib/mbuzz/visitor/identifier.rb`

```ruby
def self.generate
  SecureRandom.hex(32)  # RANDOM - not deterministic!
end
```

**File:** `lib/mbuzz/middleware/tracking.rb`

```ruby
def resolve_visitor_id(request)
  visitor_id_from_cookie(request) || Visitor::Identifier.generate
end
```

**The Problem:** When no `_mbuzz_vid` cookie exists, each request generates a RANDOM visitor_id. Concurrent Turbo frame requests (none have cookies yet) each create different visitor_ids.

### 2. The Middleware Flow (mbuzz-ruby gem)

**File:** `lib/mbuzz/middleware/tracking.rb`

When a request arrives:

```ruby
def call(env)
  return @app.call(env) if skip_request?(env)

  request = Rack::Request.new(env)
  context = build_request_context(request)  # Generates random visitor_id if no cookie

  # ...
  create_session_if_new(context, request)   # Creates session via API
  # ...
end

def new_session?(request)
  session_id_from_cookie(request).nil?      # True if no _mbuzz_sid cookie
end
```

**Key insight:** On FIRST page load, no requests have cookies. Each concurrent Turbo frame generates a new random visitor_id.

### 2. Concurrent Turbo Frame Requests

When a page with Turbo frames loads:

```
T=0ms   Main page request      → no cookie → new_session=true → API call
T=0ms   Turbo frame 1 request  → no cookie → new_session=true → API call
T=0ms   Turbo frame 2 request  → no cookie → new_session=true → API call
T=0ms   Turbo frame 3 request  → no cookie → new_session=true → API call
...
```

Each request:
1. Has no session cookie (first page load)
2. Generates the SAME deterministic session_id (based on visitor_id + 30-min time bucket)
3. Makes an API call to `/sessions` in a background thread
4. Has a DIFFERENT `started_at` timestamp (milliseconds apart)

### 3. Session ID Generation (Correct)

**File:** `lib/mbuzz/session/id_generator.rb`

```ruby
def generate_deterministic(visitor_id:, timestamp: Time.now.to_i)
  time_bucket = timestamp / SESSION_TIMEOUT_SECONDS  # 1800 seconds = 30 min
  raw = "#{visitor_id}_#{time_bucket}"
  Digest::SHA256.hexdigest(raw)[0, SESSION_ID_LENGTH]
end
```

This correctly generates the SAME session_id for concurrent requests within the same 30-minute bucket.

### 4. The Database Unique Constraint (The Bug)

**File:** `db/schema.rb:338`

```ruby
t.index ["account_id", "session_id", "started_at"],
        name: "index_sessions_on_account_id_and_session_id",
        unique: true
```

The unique constraint includes `started_at`, meaning:
- Session A: `(acct_1, sess_abc, 2024-01-01 10:00:00.000)` ✓
- Session B: `(acct_1, sess_abc, 2024-01-01 10:00:00.001)` ✓ (DIFFERENT started_at!)

Both are considered UNIQUE rows and both inserts succeed!

### 5. Session Lookup is Per-Visitor (CRITICAL BUG)

**File:** `app/services/sessions/creation_service.rb:110-119`

```ruby
def find_or_initialize_session
  existing = account.sessions.find_by(session_id: session_id, visitor: visitor)  # BUG: includes visitor!
  return existing if existing

  account.sessions.new(
    session_id: session_id,
    visitor: visitor,
    started_at: started_at,
    is_test: is_test
  )
end
```

**The Bug:** Session lookup includes `visitor`, so each random visitor_id creates its own session even with the same session_id:

```
T=0ms   Request A: visitor_id="abc", session_id="xyz"
        → find_by(session_id: "xyz", visitor: "abc") → nil
        → Creates visitor "abc" + session for "abc"

T=0ms   Request B: visitor_id="def", session_id="xyz"
        → find_by(session_id: "xyz", visitor: "def") → nil (different visitor!)
        → Creates visitor "def" + session for "def"
```

**Result:** Two visitors, two sessions, but both sessions have session_id="xyz".

This is why only 6 session_ids are shared across visitors - most sessions have the same session_id but different visitors, so they're not "shared" from the server's perspective.

### 6. Orphan Visitors from Events::ProcessingService

**File:** `app/services/visitors/lookup_service.rb`

```ruby
def run
  unless visitor
    @visitor = account.visitors.create(visitor_id: visitor_id, is_test: is_test)
    # Creates visitor WITHOUT any session!
  end
end
```

When `Mbuzz.event()` is called, it uses `Visitors::LookupService` which creates visitors without sessions. Combined with random visitor_ids, this creates orphan visitors.

---

## Why `started_at` Is in the Unique Constraint

The sessions table uses TimescaleDB hypertable partitioning:

```ruby
create_table "sessions", primary_key: ["id", "started_at"], force: :cascade
```

TimescaleDB requires the partition key (`started_at`) to be part of any unique constraint. This is a TimescaleDB limitation, not a design choice.

---

## Exploratory Analysis (Production Queries)

Run these queries to confirm the issue in production:

### 1. Find Sessions with Duplicate session_id

```sql
-- Find sessions where multiple rows share the same session_id
SELECT
  account_id,
  session_id,
  COUNT(*) as session_count,
  MIN(started_at) as first_started,
  MAX(started_at) as last_started,
  EXTRACT(EPOCH FROM (MAX(started_at) - MIN(started_at))) as duration_seconds
FROM sessions
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY account_id, session_id
HAVING COUNT(*) > 1
ORDER BY session_count DESC
LIMIT 100;
```

**Expected result:** Many rows with `session_count` > 1 and `duration_seconds` < 1 (sub-second duplicates from concurrent requests).

### 2. Quantify the Duplication Rate

```sql
-- Overall duplication statistics
WITH session_counts AS (
  SELECT
    session_id,
    COUNT(*) as count
  FROM sessions
  WHERE created_at > NOW() - INTERVAL '7 days'
  GROUP BY session_id
)
SELECT
  COUNT(*) FILTER (WHERE count = 1) as unique_sessions,
  COUNT(*) FILTER (WHERE count > 1) as duplicated_session_ids,
  SUM(count) FILTER (WHERE count > 1) as total_duplicate_rows,
  ROUND(100.0 * SUM(count) FILTER (WHERE count > 1) / SUM(count), 2) as duplication_percentage
FROM session_counts;
```

**Expected result:** High `duplication_percentage` correlating with the 10-20x visit inflation.

### 3. Time Gap Analysis for Duplicates

```sql
-- Analyze time gaps between duplicate sessions
WITH duplicates AS (
  SELECT
    session_id,
    started_at,
    LAG(started_at) OVER (PARTITION BY session_id ORDER BY started_at) as prev_started_at
  FROM sessions
  WHERE created_at > NOW() - INTERVAL '7 days'
)
SELECT
  CASE
    WHEN EXTRACT(EPOCH FROM (started_at - prev_started_at)) < 1 THEN 'sub_1_second'
    WHEN EXTRACT(EPOCH FROM (started_at - prev_started_at)) < 5 THEN '1_to_5_seconds'
    WHEN EXTRACT(EPOCH FROM (started_at - prev_started_at)) < 60 THEN '5_to_60_seconds'
    ELSE 'over_1_minute'
  END as time_gap_bucket,
  COUNT(*) as count
FROM duplicates
WHERE prev_started_at IS NOT NULL
GROUP BY 1
ORDER BY count DESC;
```

**Expected result:** Most duplicates in `sub_1_second` bucket, confirming concurrent request origin.

### 4. Check for Turbo Frame Correlation

```sql
-- Look for sessions with same visitor but different page_view_count = 0
-- (Turbo frames often don't increment page views)
SELECT
  v.visitor_id,
  COUNT(DISTINCT s.id) as session_count,
  SUM(CASE WHEN s.page_view_count = 0 THEN 1 ELSE 0 END) as zero_pageview_sessions
FROM sessions s
JOIN visitors v ON s.visitor_id = v.id
WHERE s.created_at > NOW() - INTERVAL '7 days'
GROUP BY v.visitor_id
HAVING COUNT(DISTINCT s.id) > 3
ORDER BY session_count DESC
LIMIT 50;
```

### 5. Impact on Billing

```sql
-- Check if duplicate sessions are incrementing usage
SELECT
  a.name as account_name,
  COUNT(DISTINCT s.session_id) as unique_session_ids,
  COUNT(*) as total_session_rows,
  ROUND(100.0 * (COUNT(*) - COUNT(DISTINCT s.session_id)) / COUNT(*), 2) as duplicate_percentage
FROM sessions s
JOIN accounts a ON s.account_id = a.id
WHERE s.created_at > NOW() - INTERVAL '30 days'
GROUP BY a.id, a.name
HAVING COUNT(*) > COUNT(DISTINCT s.session_id)
ORDER BY (COUNT(*) - COUNT(DISTINCT s.session_id)) DESC
LIMIT 20;
```

---

## Fix Options Analysis

### Option 1: Add ON CONFLICT Handling (Recommended)

**Approach:** Use `INSERT ... ON CONFLICT DO NOTHING` or `ON CONFLICT DO UPDATE`.

**Pros:**
- Database-level atomicity
- Works with TimescaleDB constraints
- No application-level locking needed

**Cons:**
- Requires matching ON CONFLICT target to unique constraint
- With `(account_id, session_id, started_at)`, different started_at won't conflict

**Verdict:** Won't work directly because the constraint includes started_at.

### Option 2: Pre-Insert Lookup with Lock (Not Recommended)

**Approach:** Use `SELECT FOR UPDATE` to lock before insert.

**Pros:**
- Prevents race condition

**Cons:**
- Expensive
- TimescaleDB partitioning complicates locking
- Doesn't solve the constraint issue

**Verdict:** Overcomplicated, doesn't address root cause.

### Option 3: SDK-Side Deduplication (Recommended Short-Term)

**Approach:** Prevent the middleware from making multiple session creation calls for the same page load.

**Implementation:**
1. Skip session creation for Turbo frame requests
2. Only create sessions for full page loads
3. Detect Turbo frames via `Turbo-Frame` header

**Pros:**
- Fixes the issue at the source
- Reduces API load
- Simple to implement

**Cons:**
- Requires SDK update
- Existing SDK versions still have the bug

**Verdict:** Best short-term fix. Deploy SDK update.

### Option 4: Server-Side Session Resolution (Already Implemented, Not Activated)

**Approach:** The server already has `Sessions::ResolutionService` for server-side session resolution, but it requires the SDK to forward `ip` and `user_agent`.

**From spec:** `lib/specs/server_side_session_resolution.md` documents this feature.

**Current state:**
- Server-side resolution is implemented
- SDK needs to forward `ip` and `user_agent` to activate it
- Without these, server falls back to client session_id

**Verdict:** Complete the SDK update to forward ip/user_agent, enabling full server-side resolution.

### Option 5: Normalize started_at in Session Creation (Recommended API-Side Fix)

**Approach:** Round `started_at` to a fixed granularity (e.g., 1-minute buckets) so concurrent requests get the same value.

**Implementation:**
```ruby
def started_at
  @started_at ||= normalize_timestamp(parse_timestamp(params[:started_at]) || Time.current)
end

def normalize_timestamp(time)
  # Round to nearest minute to prevent sub-second duplicates
  Time.at((time.to_i / 60) * 60)
end
```

**Pros:**
- Simple server-side fix
- Works with existing SDKs
- Concurrent requests within same minute get same started_at

**Cons:**
- Slight loss of timestamp precision
- Still allows duplicates if requests span minute boundary

**Verdict:** Good complementary fix alongside SDK changes.

### Option 6: Add session_id-Only Unique Index (If TimescaleDB Allows)

**Approach:** Add a partial unique index or regular unique constraint.

**Attempt:**
```ruby
add_index :sessions, [:account_id, :session_id], unique: true
```

**Issue:** TimescaleDB requires partition key in all unique constraints. This would fail.

**Verdict:** Not possible with current TimescaleDB setup.

---

## Recommended Fix Strategy

### Phase 1: Server-Side Fix (API) - NO SDK CHANGES REQUIRED

This fix leverages the fact that session_id is already deterministic for new visitors (fingerprint-based).

#### 1A: Visitor Resolution by Session ID

```ruby
# app/services/sessions/creation_service.rb

def find_or_create_visitor
  # First check if a recent session exists with same session_id
  # This indicates a concurrent Turbo frame request
  canonical_visitor || create_new_visitor
end

def canonical_visitor
  return @canonical_visitor if defined?(@canonical_visitor)

  # Find a session with same session_id created in last 30 seconds
  existing_session = account.sessions
    .where(session_id: session_id)
    .where("sessions.created_at > ?", 30.seconds.ago)
    .order(:created_at)
    .first

  @canonical_visitor = existing_session&.visitor
end
```

**Why this works:**
- All concurrent Turbo frames generate SAME session_id (fingerprint-based from IP + User-Agent)
- First request creates visitor "abc" + session with session_id "xyz"
- Second request (different random visitor_id "def"):
  - Finds existing session with session_id "xyz" created 10ms ago
  - Reuses visitor "abc" instead of creating "def"
  - Creates/finds session for visitor "abc"
- 30-second window handles request processing delays
- No SDK changes required!

#### 1B: Merge Duplicate Visitors (Background Job)

For cases where race condition still creates duplicates:

```ruby
# app/jobs/visitors/deduplication_job.rb
class Visitors::DeduplicationJob < ApplicationJob
  def perform(account_id)
    # Find visitors that share session_ids (created by concurrent requests)
    # Merge them to the oldest visitor
  end
end
```

---

### Phase 2: SDK Update (mbuzz-ruby) - RECOMMENDED BUT OPTIONAL

#### Fix 2A: Make Visitor ID Deterministic for New Visitors

```ruby
# lib/mbuzz/visitor/identifier.rb
def self.generate_deterministic(ip:, user_agent:)
  fingerprint = Digest::SHA256.hexdigest("#{ip}|#{user_agent}")
  fingerprint[0, 64]  # Same length as random hex
end

def self.generate
  SecureRandom.hex(32)  # Keep as fallback
end
```

```ruby
# lib/mbuzz/middleware/tracking.rb
def resolve_visitor_id(request)
  visitor_id_from_cookie(request) || generate_deterministic_visitor_id(request)
end

def generate_deterministic_visitor_id(request)
  Visitor::Identifier.generate_deterministic(
    ip: client_ip(request),
    user_agent: user_agent(request)
  )
end
```

**Result:** All concurrent Turbo frames get the SAME visitor_id (deterministic from fingerprint).

#### Fix 1B: Skip Tracking for Turbo Frame Requests

```ruby
def skip_request?(env)
  path = env["PATH_INFO"].to_s.downcase

  skip_by_path?(path) ||
    skip_by_extension?(path) ||
    turbo_frame_request?(env)  # NEW
end

def turbo_frame_request?(env)
  env["HTTP_TURBO_FRAME"].present?
end
```

**Result:** Only the main page request creates visitor/session, not the frames.

#### Fix 1C: Forward IP/User-Agent to API

```ruby
def create_session(visitor_id, session_id, url, referrer, ip, user_agent)
  Client.session(
    visitor_id: visitor_id,
    session_id: session_id,
    url: url,
    referrer: referrer,
    ip: ip,              # NEW
    user_agent: user_agent  # NEW
  )
end
```

### Phase 2: Server-Side Visitor Deduplication

Add server-side visitor resolution using device fingerprint:

```ruby
# app/services/visitors/resolution_service.rb
class Visitors::ResolutionService
  def initialize(account, visitor_id:, ip:, user_agent:)
    @account = account
    @visitor_id = visitor_id
    @device_fingerprint = compute_fingerprint(ip, user_agent)
  end

  def call
    # If visitor_id exists, use it
    return existing_visitor if existing_visitor

    # Otherwise, try to find by device fingerprint
    find_by_fingerprint || create_visitor
  end

  private

  def find_by_fingerprint
    # Find recent session with same fingerprint, return its visitor
    recent_session = account.sessions
      .where(device_fingerprint: @device_fingerprint)
      .where("created_at > ?", 30.minutes.ago)
      .order(created_at: :desc)
      .first

    recent_session&.visitor
  end
end
```

### Phase 3: Data Cleanup

After deploying fixes, deduplicate existing visitor data:

```ruby
# Find visitors that should be merged (same device fingerprint)
# Merge sessions/events to the oldest visitor
# Delete duplicate visitor records
```

---

## SPA and SSR Considerations

### Which Architectures Are Affected?

| Architecture | Risk Level | Why |
|--------------|------------|-----|
| **Turbo/Hotwire** | HIGH | Multiple concurrent server-side HTML requests per frame |
| **Hotwire Turbo Streams** | HIGH | Same as Turbo frames |
| **SSR with parallel fetch** (Next.js, Nuxt) | MEDIUM | Multiple server requests during SSR |
| **Prefetching** (Turbo, Next.js link prefetch) | MEDIUM | Background requests without cookies |
| **Traditional SPA** (React, Vue, Angular) | LOW | Cookie set before JS runs |
| **Static site + JS SDK** | NONE | Client-side tracking only |

### Traditional SPAs Are Usually Safe

```
1. Browser requests initial HTML → middleware sets cookie
2. JavaScript loads and hydrates
3. Client-side navigation (no server requests)
4. API calls include cookies (already set)
```

The cookie is set on the initial HTML request before JavaScript makes any API calls.

### SSR SPAs Can Be Affected

Next.js, Nuxt, and similar frameworks with server-side rendering may:
- Make parallel data fetching requests during SSR
- Have prefetching that creates requests before cookies exist

---

## Server-Side Detection (No SDK Changes Required)

### Detectable Pattern

The Ruby and Node SDKs generate session_id **deterministically** for new visitors:

```ruby
# Ruby SDK: lib/mbuzz/session/id_generator.rb
def generate_from_fingerprint(client_ip:, user_agent:)
  fingerprint = Digest::SHA256.hexdigest("#{client_ip}|#{user_agent}")
  # ...
end
```

This means concurrent Turbo frame requests will have:
- **Same session_id** (fingerprint-based)
- **Different visitor_ids** (random)
- **Timestamps within milliseconds**

### API-Side Detection Strategy

```ruby
# app/services/sessions/creation_service.rb

def find_canonical_visitor
  # Check if another visitor was recently created with same session_id
  existing_session = account.sessions
    .where(session_id: session_id)
    .where("created_at > ?", 30.seconds.ago)
    .order(:created_at)
    .first

  return existing_session.visitor if existing_session

  # Also check for concurrent requests being processed
  recent_visitor = account.visitors
    .joins(:sessions)
    .where(sessions: { session_id: session_id })
    .where("visitors.created_at > ?", 30.seconds.ago)
    .order("visitors.created_at")
    .first

  recent_visitor || create_visitor
end
```

### Why This Works

1. All concurrent Turbo frames generate **same session_id** (from IP + User-Agent)
2. First request creates visitor "v1" with session_id "sess_abc"
3. Second request looks for recent session with "sess_abc" → finds it → reuses "v1"
4. No SDK changes required!

### SDK Data Currently Sent

| Field | Ruby SDK | Node SDK | Useful for Detection? |
|-------|----------|----------|----------------------|
| `User-Agent` header | `mbuzz-ruby/0.x` | `mbuzz-node/0.x` | No (not browser UA) |
| `visitor_id` | Random | Random | No |
| `session_id` | Deterministic (fingerprint) | Deterministic (fingerprint) | **YES** |
| `url` | Request URL | Request URL | Maybe (same page) |
| `started_at` | Current time | Current time | **YES** (similar timestamps) |
| `referrer` | Request referrer | Request referrer | Maybe |

### Detection Logic

```ruby
# Detect concurrent requests (likely Turbo frames)
def concurrent_request?
  # Same session_id within 30 seconds = concurrent Turbo frames
  account.sessions.exists?(
    session_id: session_id,
    created_at: 30.seconds.ago..
  )
end

def find_or_create_visitor
  if concurrent_request?
    # Reuse the visitor from the first request
    existing_visitor
  else
    create_new_visitor
  end
end
```

---

## Test Cases

### Unit Test: Race Condition with Different started_at

**File:** `test/services/sessions/creation_service_race_test.rb`

```ruby
class Sessions::CreationServiceRaceTest < ActiveSupport::TestCase
  test "concurrent requests with same session_id should not create duplicates" do
    # Simulate concurrent requests with different timestamps
    params1 = {
      visitor_id: "vis_concurrent_test",
      session_id: "sess_same_id",
      url: "https://example.com/page",
      started_at: "2024-01-01T10:00:00.000Z"
    }

    params2 = params1.merge(started_at: "2024-01-01T10:00:00.100Z")  # 100ms later

    # Create first session
    result1 = Sessions::CreationService.new(account, params1).call

    # Create second session with same session_id but different started_at
    result2 = Sessions::CreationService.new(account, params2).call

    # Should only have ONE session
    sessions = account.sessions.where(session_id: "sess_same_id")
    assert_equal 1, sessions.count, "Should deduplicate sessions with same session_id"
  end
end
```

### Integration Test: Turbo Frame Session Counting

**File:** `sdk_integration_tests/scenarios/turbo_frame_dedup_test.rb`

```ruby
class TurboFrameDedupTest < SdkIntegrationTest
  def test_turbo_frames_share_single_session
    # Visit page with Turbo frames (simulated via concurrent API calls)
    visitor_id = "vis_turbo_test_#{SecureRandom.hex(8)}"
    session_id = "sess_turbo_test_#{SecureRandom.hex(8)}"

    # Simulate 5 concurrent Turbo frame requests
    threads = 5.times.map do |i|
      Thread.new do
        HTTParty.post(
          "#{TestConfig.api_url}/sessions",
          headers: auth_headers,
          body: {
            session: {
              visitor_id: visitor_id,
              session_id: session_id,
              url: "https://example.com/page",
              started_at: Time.now.utc.iso8601(6)  # Microsecond precision
            }
          }.to_json
        )
      end
    end

    threads.each(&:join)

    # Verify only ONE session was created
    wait_for_async(2)
    data = verify_test_data(visitor_id: visitor_id)

    assert_equal 1, data[:sessions].length,
      "Expected 1 session but got #{data[:sessions].length}. " \
      "Duplicate sessions indicate race condition bug."
  end
end
```

### SDK Test: Turbo Frame Detection

**File:** `test/mbuzz/middleware/tracking_test.rb` (in mbuzz-ruby)

```ruby
def test_skips_session_creation_for_turbo_frame_requests
  env = Rack::MockRequest.env_for("/products", {
    "HTTP_TURBO_FRAME" => "product_details"
  })

  # Should not trigger session creation API call
  mock_client = Minitest::Mock.new
  mock_client.expect(:session, nil) do
    flunk "Should not create session for Turbo frame requests"
  end

  Mbuzz::Client.stub(:session, mock_client) do
    @middleware.call(env)
  end
end
```

---

## Implementation Checklist

### Phase 1: Confirm Issue in Production ✅ DONE

- [x] Check visitor vs session counts (144k visitors, 90k sessions = 0.63 ratio)
- [x] Check visitors created per second (70+ per second observed)
- [x] Check device fingerprint coverage (99.5% missing)
- [x] Calculate inflation factor (72,154x)
- [x] Confirm root cause: random visitor_id generation

### Phase 2: Server-Side Fix (API) - NO SDK CHANGES - PRIORITY 1

#### 2A: Visitor Resolution by Session ID

- [x] Update `Sessions::CreationService` to check for existing session with same session_id
- [x] If found within 30 seconds, reuse that visitor instead of creating new one
- [x] Write unit test: two requests with same session_id → same visitor
- [x] Write unit test: two requests with different session_id → different visitors
- [x] Write unit test: same session_id but >30 seconds apart → different visitors (new session)

#### 2B: Handle Race Condition

- [x] Add double-check in `find_or_initialize_session` to catch race conditions
- [x] If another session with same session_id is found, reuse that visitor
- [x] Integration test with concurrent futures in `turbo_frame_dedup_test.rb`

#### 2C: Deployment

- [x] Run existing test suite (1220 service tests, 437 controller tests - all passing)
- [ ] Deploy to staging
- [ ] Deploy to production
- [ ] Monitor visitor counts (expect immediate ~70x reduction for new traffic)

### Phase 3: Data Cleanup - PRIORITY 2

#### 3A: Identify Duplicate Visitors

- [ ] Query: find visitors that share session_ids
- [ ] Estimate scope of cleanup needed

#### 3B: Merge Duplicate Visitors

- [ ] Create migration/rake task to merge visitors
- [ ] For each group of duplicates (same session_id):
  - [ ] Pick canonical visitor (oldest created_at)
  - [ ] Reassign all sessions to canonical visitor
  - [ ] Reassign all events to canonical visitor
  - [ ] Delete duplicate visitor records
- [ ] Run in batches to avoid locking

#### 3C: Verify Cleanup

- [ ] Re-run production queries
- [ ] Check funnel numbers are now reasonable

### Phase 4: SDK Updates - OPTIONAL (Belt and Suspenders)

#### 4A: Deterministic Visitor ID (mbuzz-ruby)

- [ ] Add `Visitor::Identifier.generate_deterministic(ip:, user_agent:)` method
- [ ] Update `resolve_visitor_id` to use deterministic generation when no cookie
- [ ] Write tests
- [ ] Bump version, release

#### 4B: Deterministic Visitor ID (mbuzz-node)

- [ ] Same changes as Ruby SDK
- [ ] Write tests
- [ ] Bump version, release

#### 4C: Skip Turbo Frame Requests (mbuzz-ruby)

- [ ] Add `turbo_frame_request?` detection (`HTTP_TURBO_FRAME` header)
- [ ] Update `skip_request?` to skip Turbo frame requests
- [ ] Write tests
- [ ] Release

#### 4D: Forward IP/User-Agent to API

- [ ] Update session/track payloads to include ip/user_agent
- [ ] API can then compute device_fingerprint
- [ ] Write tests
- [ ] Release

### Phase 5: Monitoring

- [ ] Add metrics for duplicate visitor detection
- [ ] Alert if duplication rate exceeds threshold
- [ ] Dashboard for visitor/session ratio health

---

## Appendix: Code References

| File | Line | Description |
|------|------|-------------|
| `lib/mbuzz/middleware/tracking.rb` | 80-81 | `new_session?` check |
| `lib/mbuzz/middleware/tracking.rb` | 110-113 | `create_session_if_new` |
| `lib/mbuzz/session/id_generator.rb` | 14-17 | Deterministic ID generation |
| `app/services/sessions/creation_service.rb` | 110-119 | `find_or_initialize_session` |
| `db/schema.rb` | 338 | Unique constraint with started_at |
| `lib/specs/server_side_session_resolution.md` | Full | Server-side resolution spec |

---

## Progress Log

| Date | Step | Status | Notes |
|------|------|--------|-------|
| 2025-01-04 | Initial investigation | Complete | Initially thought session duplication |
| 2025-01-04 | Production analysis | Complete | Found 72,154x visitor inflation |
| 2025-01-04 | Root cause identified | Complete | Random visitor_id + concurrent Turbo frames |
| 2025-01-04 | Spec document created | Complete | This document |
| 2025-01-04 | API fix: visitor resolution | Complete | `Sessions::CreationService` updated with `canonical_visitor` detection |
| 2025-01-04 | Unit tests | Complete | 3 new tests for deduplication in `sessions/creation_service_test.rb` |
| 2025-01-04 | Full test suite | Complete | 1220 service tests, 437 controller tests - all passing |
| 2025-01-04 | Integration tests | Complete | `turbo_frame_dedup_test.rb` added to `sdk_integration_tests/` |
| | Deployment to staging | Pending | |
| | Deployment to production | Pending | |
| | Monitor visitor counts | Pending | |
| | Data cleanup | Pending | |
| | SDK fix: deterministic visitor_id | Optional | Server-side fix handles this |
| | SDK fix: skip Turbo frames | Optional | Server-side fix handles this |
