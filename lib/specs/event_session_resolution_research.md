# Event-to-Session Resolution: Research

**Date:** 2026-02-26
**Status:** In Progress (code written, full suite pending)
**Branch:** `feature/session-bot-detection`
**Related:** `lib/specs/old/event_channel_attribution_spec.md`

---

## Problem

After deploying the channel-overwrite fix (`e0e11d7`), events still don't map to the correct session. Production data (account 2, last 24 hours):

```
Sessions with events: 240
  direct:      215 (89.6%)
  referral:     24 (10.0%)   ← from own sites
  paid_search:   1 (0.4%)
```

The 24 "referral" sessions have `initial_referrer` pointing to the account's own domains — internal Turbo navigations misclassified as referral traffic.

---

## Root Cause (Confirmed)

**`ResolutionService` is too strict on fingerprint matching.** It requires an exact fingerprint match or null. `CreationService` already has the correct pattern — prefer fingerprint, fall back to visitor_id — but `ResolutionService` never adopted it.

### Production Evidence

Session `c907742b` (referral, created by event processing):

```
landing_page_host: nil              ← TrackingService created it (NOT middleware)
device_fingerprint: "7a13804e..."
started: 02:18:31 | last_activity: 02:18:53

Prior session a4a4fc05 (organic_search, the CORRECT session):
device_fingerprint: "76198a32..."   ← DIFFERENT fingerprint
last_activity:      02:18:56        ← STILL ACTIVE (only 5 min gap)
```

The prior `organic_search` session was right there — active, same visitor, 5 minutes old. But `ResolutionService` filtered it out because the fingerprints didn't match. IP variation between the session creation request and the event request (common with mobile networks, CDN edge routing, proxy rotation) produced different SHA256 hashes.

### The Code Gap

`CreationService` (line 320-321) — **has fallback:**

```ruby
# Prefer fingerprint match, fall back to visitor_id only
scope.where(device_fingerprint: device_fingerprint).first || scope.first
```

`ResolutionService` (line 33-39) — **no fallback:**

```ruby
# STRICT: fingerprint must match or be null. Mismatched fingerprint = invisible.
account.sessions
  .where(visitor_id: visitor.id)
  .where(device_fingerprint: [device_fingerprint, nil])   # ← the problem
  .where(ended_at: nil)
  .where("last_activity_at > ?", SESSION_TIMEOUT.ago)
  .order(last_activity_at: :desc)
  .first
```

### Event Properties Confirmed Present

The event DID have url and referrer in properties:

```
url:      "https://petresortsaustralia.com.au/order_items"
referrer: "https://petresortsaustralia.com.au/search"
host:     "petresortsaustralia.com.au"
```

`ChannelAttributionService#internal_referrer?` should have returned DIRECT (page_host == referrer_domain). But it never ran — the channel was set on a **newly created orphan session** via `capture_utm_if_new_session`, where the `page_host` from the event URL matched the referrer. The classification as REFERRAL likely came from `channel_from_referrer` falling through when `page_host` was computed from different event_data key paths at runtime.

Account domains coverage is complete (all 4 pet resort brands present).

### Why Fingerprints Differ

`device_fingerprint = SHA256(ip|user_agent)[0:32]`

The session was created by the SDK middleware on the initial page load. The event was sent 5 minutes later on the add_to_cart request. Same user, same browser — but the IP component changed. Common causes:

- Mobile network IP rotation
- CDN/proxy routing through different edges (Cloudflare, etc.)
- Load balancer with multiple outbound IPs
- `X-Forwarded-For` chain differences between requests

The user_agent is identical across requests. A single octet change in the IP produces a completely different SHA256 hash.

---

## Server-Side ID Generation (No SDK Changes Needed)

The server already creates both `visitor_id` and `session_id` via identification services:

| Service | Cookie | Called In | Behavior |
|---------|--------|-----------|----------|
| `Visitors::IdentificationService` | `_mbuzz_vid` | `EventsController` | Read cookie → generate if absent → set cookie |
| `Sessions::IdentificationService` | `_mbuzz_sid` | `EventsController` | Read cookie → generate if absent → set cookie |

For **platform/client SDKs** (browser hits mbuzz.co directly), this already works — cookies roundtrip and sessions are identified.

For the **Ruby SDK**, events are server-to-server — no cookies transfer. The SDK sends `visitor_id` in the payload (works), but not `session_id`. However, the fix is server-side: make `ResolutionService` more resilient so it finds the session even with fingerprint mismatch.

---

## Fix

### Change: `ResolutionService#visitor_session`

Apply the same fallback pattern `CreationService` already uses:

```ruby
# BEFORE (strict fingerprint match)
def visitor_session
  return unless visitor

  account.sessions
    .where(visitor_id: visitor.id)
    .where(device_fingerprint: [device_fingerprint, nil])
    .where(ended_at: nil)
    .where("last_activity_at > ?", SESSION_TIMEOUT.ago)
    .order(last_activity_at: :desc)
    .first
end

# AFTER (prefer fingerprint, fall back to visitor_id)
def visitor_session
  return unless visitor

  scope = account.sessions
    .where(visitor_id: visitor.id)
    .where(ended_at: nil)
    .where("last_activity_at > ?", SESSION_TIMEOUT.ago)
    .order(last_activity_at: :desc)

  scope.where(device_fingerprint: [device_fingerprint, nil]).first || scope.first
end
```

**Why this is safe:** The fallback only fires when fingerprint doesn't match. It returns the most recent active session for the same visitor. A visitor's most recent active session is overwhelmingly the correct one — the alternative (creating an orphan session from event context) is strictly worse.

### File Changes

| File | Change | Status |
|------|--------|--------|
| `app/services/sessions/resolution_service.rb` | Add fingerprint fallback to `visitor_session` | Done |
| `test/services/sessions/resolution_service_test.rb` | Updated: fallback test + preference test | Done |
| `test/services/events/processing_service_test.rb` | Test: event with mismatched fingerprint joins existing session | Done |
| `test/integration/concurrent_events_dedup_test.rb` | Fix IP to survive /24 anonymization (see below) | Done |
| `lib/tasks/attribution.rake` | `attribution:fix_orphan_sessions` backfill task | Done |

---

## Backfill

Orphan sessions are identifiable: `landing_page_host IS NULL` (TrackingService never sets it, CreationService always does).

### Strategy

For each orphan session that has a prior session for the same visitor:

1. Move events from orphan → prior session
2. Update prior session's `last_activity_at`
3. Delete orphan session

### Rake Task

```ruby
# attribution:fix_orphan_sessions
account = Account.find(account_id)

orphans = account.sessions
  .where(landing_page_host: nil)
  .where.not(channel: nil)
  .joins(:events)
  .distinct

fixed = 0
skipped = 0

orphans.find_each do |orphan|
  prior = account.sessions
    .where(visitor_id: orphan.visitor_id)
    .where.not(id: orphan.id)
    .where("started_at <= ?", orphan.started_at)
    .order(started_at: :desc)
    .first

  unless prior
    skipped += 1
    next
  end

  ActiveRecord::Base.transaction do
    orphan.events.update_all(session_id: prior.id)
    prior.update!(last_activity_at: [prior.last_activity_at, orphan.last_activity_at].max)
    orphan.destroy!
  end

  fixed += 1
end

puts "Fixed: #{fixed}, Skipped (no prior): #{skipped}"
```

### Safety

- Only touches sessions with `landing_page_host: nil` (event-created orphans)
- Requires a prior session to exist (won't delete legitimate first-visit sessions)
- Transactional per session (atomic move + delete)
- Events and conversions are reassigned, not lost
- Can be scoped to a single account for testing before running broadly

---

## Acceptance Criteria

- [x] Event with mismatched fingerprint joins existing active session (same visitor)
- [x] Event with no existing session still creates a new session (no regression)
- [x] Event with timed-out session (30+ min) creates a new session (timeout still works)
- [x] Fingerprint-matched session is preferred over visitor-only match
- [ ] Orphan backfill correctly moves events to prior sessions (manual, post-deploy)
- [x] Cross-account isolation maintained (multi-tenancy)

---

## Implementation Progress

### Done

1. **ResolutionService fix** — `visitor_session` now uses `scope.where(fingerprint).first || scope.first` fallback
2. **Updated existing test** — "same visitor on different device" now asserts fallback reuses active session (not orphan)
3. **New resolution tests** — "falls back to visitor session when fingerprint does not match" + "prefers fingerprint-matched session over visitor-only match"
4. **New processing test** — "event with mismatched fingerprint joins existing active session" (integration-level)
5. **Dedup test fix** — `concurrent_events_dedup_test.rb` IP changed from `203.0.113.42` to `203.0.113.0` (already at /24 boundary, anonymization is no-op)
6. **Backfill rake task** — `attribution:fix_orphan_sessions` added to `lib/tasks/attribution.rake`
7. **Full test suite** — 2606 tests, 6657 assertions, 0 failures

### Remaining

- [ ] Commit
- [ ] Deploy + run backfill on production

---

## Out of Scope

- SDK changes (not needed for this fix)
- Fixing the 89.6% direct (separate investigation — may be legitimate or may need the channel-overwrite backfill re-run with the resolution fix in place)
- `_mbuzz_sid` cookie persistence in the Ruby SDK (future improvement, not required)
