# Session Continuity Fix — Ghost Sessions & Conversion Misattribution

**Date:** 2026-02-09
**Priority:** P0
**Status:** Implementation complete — see `session_continuity_rollout_spec.md` for deploy plan
**Branch:** `feature/e1s4-content`

---

## Summary

Production data proves that **every SDK request creates a new server-side session** instead of extending the existing browsing session. This causes:
- **341k ghost sessions** in 90 days (98-100% of all sessions have 0 events)
- **Conversion misattribution**: User lands from Google (paid_search), but the conversion links to a later internal-navigation session classified as "referral"
- **Session inflation**: One converting visitor has 1,252 sessions across all channels

The root cause is in `Sessions::CreationService#find_or_initialize_session`. The SDK generates a new UUID for `session_id` on every request. The server looks up by `session_id` (never matches), then creates a new session. The 30-second fingerprint dedup window only catches concurrent requests, not normal browsing.

**The fix**: Before creating a new session, check if the visitor already has an active session (within 30-minute sliding window). If yes, and the current request is not a new traffic source, reuse it.

---

## Production Evidence (2026-02-09, Account 2)

### H1 CONFIRMED: Conversions link to wrong session

30/30 sampled conversions show the pattern:
- `conversion_channel = referral` (from `petresortsaustralia.com.au/search`)
- `landing_channel = paid_search` or `organic_search` (from `google.com` with UTM)

The visitor's FIRST session has the correct attribution. The conversion links to a LATER session created during internal navigation.

```
conv=3120 | conv_ch=referral  | land_ch=paid_search    | land_utm={"utm_medium":"cpc","utm_source":"google","utm_campaign":"21680157495"}
conv=3124 | conv_ch=referral  | land_ch=paid_search    | land_utm={"utm_term":"dog hotel","utm_medium":"cpc","utm_source":"google"}
conv=3160 | conv_ch=referral  | land_ch=organic_search | land_ref=https://www.google.com/
conv=3478 | conv_ch=direct    | land_ch=organic_search | land_ref=https://www.google.com/
conv=3137 | conv_ch=referral  | land_ch=organic_search | land_utm={"utm_term":"plcid_7673278614692400560"}
```

### H2 CONFIRMED: Ghost sessions still being created (v0.7.3 deployed today)

SDK v0.7.3 navigation detection is not preventing ghost sessions. 98-100% ghost rate persists across all 48 hours sampled, including post-deployment.

```
2026-02-09 05:00 UTC | total=1507 | ghosts=1486 (98.6%)
2026-02-09 04:00 UTC | total=1591 | ghosts=1577 (99.1%)
2026-02-09 03:00 UTC | total=1381 | ghosts=1361 (98.6%)
```

Likely cause: reverse proxy (nginx/CDN) strips `Sec-Fetch-*` headers. The SDK fallback only catches Turbo Frames, not Turbo Drive requests. **This is an SDK bug to fix separately** — the server-side fix in this spec makes navigation detection less critical.

### H5 CONFIRMED: Extreme session inflation

Converting visitors have hundreds to thousands of sessions:

```
visitor=071599... | sessions=1252 | channels={direct,email,organic_search,organic_social,other,paid_search,paid_social,referral}
visitor=f1fcc0... | sessions=836  | channels={direct,email,organic_search,organic_social,paid_search,paid_social,referral}
visitor=4bdb6b... | sessions=31   | span=13 minutes (2.4 sessions/minute)
```

---

## Current State (Broken)

### `Sessions::CreationService#find_or_initialize_session` (line 189)

```ruby
def find_or_initialize_session
  existing_for_visitor = account.sessions.find_by(session_id: session_id, visitor: visitor)
  return existing_for_visitor if existing_for_visitor         # Never matches (UUID always new)

  existing_any = recent_session_with_same_id
  return adopt_existing_session(existing_any) if existing_any  # Never matches (same UUID)

  account.sessions.new(...)                                    # Always creates new
end
```

SDK sends `session_id: SecureRandom.uuid` on every request (session cookie removed in v0.7.0). The server always creates a new session because the UUID never matches.

### `Sessions::ResolutionService#visitor_session` (line 28)

```ruby
def visitor_session
  account.sessions
    .where(visitor_id: visitor.id)
    .where(device_fingerprint: [device_fingerprint, nil])
    .where("last_activity_at > ?", SESSION_TIMEOUT.ago)  # 30 min
    .order(last_activity_at: :desc)
    .first
end
```

Event processing picks the MOST RECENTLY ACTIVE session. If a new session was just created by the SDK middleware (async), the event links to it instead of the landing session.

### `Conversions::TrackingService#resolved_session` (line 104)

```ruby
def resolved_session
  @resolved_session ||= event&.session ||
    resolved_visitor&.sessions&.order(started_at: :desc)&.first
end
```

Conversion inherits the event's session. Wrong session cascades to wrong attribution.

### Data Flow (Current — Broken)

```
User clicks Google Ad → lands on petresortsaustralia.com.au/?utm_source=google&utm_medium=cpc
  SDK: POST /api/v1/sessions {session_id: "uuid-1", url: "https://...", referrer: "google.com"}
  Server: find_or_initialize_session → uuid-1 not found → CREATE Session A (paid_search) ✅

User clicks "Search" link (Turbo Drive or native)
  SDK: POST /api/v1/sessions {session_id: "uuid-2", url: "https://.../search", referrer: "https://.../"}
  Server: find_or_initialize_session → uuid-2 not found → CREATE Session B (self-referral → "referral") ❌

User clicks "Add to Cart" (form POST)
  SDK: POST /api/v1/sessions {session_id: "uuid-3", ...} → CREATE Session C (self-referral)
  App: Mbuzz.track("add_to_cart") → POST /api/v1/events
  Server: ResolutionService → most recent active session → Session C (or B)
  Event links to Session C → channel = "referral" ❌

Conversion created → inherits Session C's channel → "referral" ❌
Dashboard: conversion attributed to "referral" instead of "paid_search"
```

---

## Proposed Solution

### Fix: Session Continuity via Active Session Reuse

In `find_or_initialize_session`, after existing checks, look for an **active session** for the same visitor+fingerprint within the 30-minute sliding window. If found, reuse it — unless the current request brings a new traffic source (UTM, click_ids, or external referrer).

### Data Flow (Proposed — Fixed)

```
User clicks Google Ad → lands on petresortsaustralia.com.au/?utm_source=google
  SDK: POST /api/v1/sessions {session_id: "uuid-1", ...}
  Server: no active session → new_traffic_source? YES (UTM) → CREATE Session A (paid_search) ✅

User clicks "Search" link
  SDK: POST /api/v1/sessions {session_id: "uuid-2", referrer: ".../"}
  Server: active_visitor_session → Session A (5 sec ago) → new_traffic_source? NO → REUSE Session A
  Session A: last_activity_at updated ✅

User clicks "Add to Cart"
  SDK: POST /api/v1/sessions {session_id: "uuid-3", referrer: ".../search"}
  Server: active_visitor_session → Session A (2 min ago) → new_traffic_source? NO → REUSE Session A
  App: Mbuzz.track("add_to_cart") → event links to Session A (paid_search) ✅

Conversion created → Session A → channel = "paid_search" ✅
```

### Key Changes

| File | Change |
|------|--------|
| `app/services/sessions/creation_service.rb` | Add `active_visitor_session` lookup + `new_traffic_source?` gate in `find_or_initialize_session` |
| `app/services/sessions/creation_service.rb` | Guard `create_or_update_session` to only update `last_activity_at` when reusing |
| `test/services/sessions/creation_service_test.rb` | New tests for session reuse and new traffic source behavior |

### Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Where to fix | `CreationService` (session creation) | Fixes root cause — one session per visit. Events and conversions automatically link to the right session. |
| Reuse window | 30 minutes (matches `ResolutionService.SESSION_TIMEOUT`) | Standard session timeout. Consistent with event resolution. |
| New traffic source detection | UTM present OR click_ids present OR external referrer | Matches GA4 behavior: new campaign = new session. |
| What about `page_host` nil? | Conservative: treat as internal (reuse session) | If we can't determine external vs internal, safer to reuse than create a new orphan session. |
| `host_from_referrer` fallback | Keep as belt-and-suspenders | Defensive measure for the edge case where URL truly has no host. |

---

## All States

| # | State | Condition | Expected Behavior |
|---|-------|-----------|-------------------|
| 1 | First visit (landing) | No active session, has UTM | Create new session (paid_search) |
| 2 | First visit (organic) | No active session, Google referrer | Create new session (organic_search) |
| 3 | First visit (direct) | No active session, no referrer/UTM | Create new session (direct) |
| 4 | Internal navigation | Active session exists, same-domain referrer | Reuse session, update last_activity_at |
| 5 | Internal navigation | Active session exists, no referrer | Reuse session, update last_activity_at |
| 6 | New campaign mid-visit | Active session exists, new UTM params | Create new session (new attribution) |
| 7 | New click_id mid-visit | Active session exists, gclid/fbclid in URL | Create new session (new attribution) |
| 8 | External referrer mid-visit | Active session exists, referrer from different domain | Create new session (referral) |
| 9 | Return after timeout | No active session (>30 min idle), no UTM | Create new session (direct) |
| 10 | Return after timeout + ad | No active session, has UTM | Create new session (paid_search) |
| 11 | No fingerprint | `device_fingerprint` nil | Skip active session check, create new (existing behavior) |
| 12 | Concurrent requests | Same fingerprint within 30s | Existing dedup logic handles this (unchanged) |
| 13 | page_host nil | Can't determine if referrer is external | Treat as internal → reuse session (conservative) |

---

## Implementation Tasks

### Phase 1: Session Continuity (CreationService)

- [x] **1.1** Add `active_visitor_session` method — finds existing session by visitor+fingerprint within 30-min window
- [x] **1.2** Add `new_traffic_source?` method — returns true when request has UTM, click_ids, or external referrer
- [x] **1.3** Add `external_referrer?` helper — compares referrer host to page_host
- [x] **1.4** Update `find_or_initialize_session` to reuse active session when not a new traffic source
- [x] **1.5** Guard `create_or_update_session` — when reusing, only update `last_activity_at`, don't overwrite attribution
- [x] **1.6** Add `host_from_referrer` fallback to `page_host` (belt-and-suspenders for nil host edge case)

### Phase 2: Tests

- [x] **2.1** Test: internal navigation reuses existing session (same session returned)
- [x] **2.2** Test: new UTM creates new session even with active session
- [x] **2.3** Test: new click_id creates new session
- [x] **2.4** Test: external referrer creates new session
- [x] **2.5** Test: same-domain referrer reuses session (covered by 2.1)
- [x] **2.6** Test: no referrer reuses session (direct continuation)
- [x] **2.7** Test: expired session (>30 min) creates new session
- [x] **2.8** Test: no fingerprint falls back to existing behavior
- [x] **2.9** Test: reused session preserves original attribution (UTM, channel, referrer)
- [x] **2.10** Test: reused session updates last_activity_at
- [x] **2.11** Test: reused session does NOT increment billing usage

### Phase 3: Documentation

- [x] **3.1** Update `lib/docs/architecture/server_side_attribution_architecture.md` with session continuity behavior
- [x] **3.2** Update data integrity runbook with new diagnostic queries

---

## Testing Strategy

### Unit Tests

| Test | Verifies |
|------|----------|
| Internal nav reuses session | `find_or_initialize_session` returns existing session |
| New UTM creates new session | `new_traffic_source?` detects UTM |
| New click_id creates new session | `new_traffic_source?` detects click_ids |
| External referrer creates new session | `external_referrer?` compares hosts |
| Same-domain referrer reuses | `external_referrer?` returns false for same host |
| No referrer reuses | Default to internal (reuse) |
| Expired session creates new | 30-min window enforced |
| Attribution preserved on reuse | Original UTM/channel/referrer unchanged |
| last_activity_at updated on reuse | Sliding window extended |
| No billing increment on reuse | `session_created?` returns false |

### Production Validation

After deployment, run the H1/H2/H5 queries again:
1. Ghost session rate should drop from 98% to <5%
2. Converting visitors should have 1-3 sessions per visit (not 100+)
3. Conversion channel should reflect landing session attribution

---

## Definition of Done

- [x] All implementation tasks completed
- [x] All tests pass (unit + existing session tests + e2e)
- [x] No regressions in existing channel classification
- [ ] Ghost session rate drops post-deployment
- [ ] Conversion attribution matches landing session channel
- [x] Spec updated with final state

---

## Out of Scope

- **SDK navigation detection fix**: Separate SDK bug. Server-side fix makes it less critical but it should still be fixed for efficiency (fewer API calls).
- **Historical data repair**: Ghost session purge + conversion reattribution can happen after this fix is deployed and validated. Existing `DataRepair::` services handle this.
- **Multi-touch attribution**: This fix ensures correct first-touch/last-touch. Multi-touch (journey_session_ids) is a separate feature.
- **`initial_url` column**: Useful for debugging but not required for the fix. Separate migration.

---

## SDK Navigation Detection (Separate Issue)

v0.7.3 navigation detection gates on `Sec-Fetch-Mode: navigate`. If the reverse proxy strips `Sec-Fetch-*` headers, the fallback only checks for Turbo Frame headers — not Turbo Drive. This needs a separate SDK fix:

**Option A**: Add `Accept` header check — Turbo Drive sends `Accept: text/vnd.turbo-stream.html, text/html` which differs from cold loads.

**Option B**: Add `Turbo-Referrer` detection — Turbo Drive sets a custom referrer header.

**Option C**: Check HTTP method — internal form POSTs with self-referral are likely internal navigation.

**Option D**: Forward `Sec-Fetch-*` headers in the reverse proxy config (nginx: `proxy_pass_request_headers on` is default but may be overridden).

This is tracked separately from the server-side fix.
