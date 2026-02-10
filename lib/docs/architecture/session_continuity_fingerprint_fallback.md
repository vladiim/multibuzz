# Session Continuity: Visitor-ID Fallback for Fingerprint Instability

**Date:** 2026-02-11
**Status:** Implementing
**Branch:** `feature/e1s4-content`

---

## Problem

Session continuity (deployed 2026-02-10) requires an exact `device_fingerprint` match to reuse an active session. The fingerprint is `SHA256(ip|user_agent)[0:32]`, computed server-side.

Production data shows **100% of misattributed conversions have different fingerprints** between the landing session and the conversion session — even for the same visitor browsing the same site seconds apart. The IP shifts between requests (CDN/proxy/load balancer rotation), producing a different fingerprint on each page load.

### Impact

- **43/43 referral conversions** in the 24h post-deploy window were misattributed
- 20 should have been `paid_search`, 16 `organic_search`, 4 `direct`, 1 `email`
- `organic_search` showed 722 sessions but **0 events** — events linked to self-referral sessions instead
- Session continuity was active (92% inflation reduction) but only for same-fingerprint requests

### Evidence (2026-02-11, Account 2)

```
=== SUMMARY ===
  Fingerprint: 0 same, 35 different
  Landing session: 37 open, 0 ended
  Time gap: 22 within 30min, 14 timed out
  Total: 37
```

All 37 misattributed conversions with a search-channel landing session had:
- Different fingerprint (100%)
- Landing session still open (100%)
- 22 of 37 within the 30-minute window (59%)

### Simulation

Visitor-ID-only matching would have caught all 43 cases:

```
Total referral conversions: 43
Would reuse correct session: 43
No active session found: 0
```

Projected channel distribution after fix:
- `direct`: 23 (36%)
- `organic_search`: 19 (30%)
- `paid_search`: 16 (25%)
- `email`: 6 (9%)
- `referral`: 0 (0%)

---

## Root Cause

`Sessions::CreationService#find_active_visitor_session` (line 280):

```ruby
def find_active_visitor_session
  return unless device_fingerprint.present?

  account.sessions
    .where(visitor_id: visitor.id)
    .where(device_fingerprint: device_fingerprint)
    .where(ended_at: nil)
    .where("last_activity_at > ?", 30.minutes.ago)
    .order(last_activity_at: :desc)
    .first
end
```

Two failure modes:
1. **Fingerprint nil** → bails out immediately, no session reuse
2. **Fingerprint changed** → no match on `device_fingerprint`, no session reuse

In both cases, a new session is created. That session inherits the self-referral channel ("referral" or "direct"), and subsequent events + conversions link to it instead of the original landing session.

---

## Fix

Fall back to `visitor_id`-only matching when fingerprint doesn't match. The `visitor_id` is an SDK-generated UUID stored in a browser cookie — same cookie = same browser = same visitor. It's a stronger identity signal than fingerprint for same-domain navigation.

```ruby
def find_active_visitor_session
  scope = account.sessions
    .where(visitor_id: visitor.id)
    .where(ended_at: nil)
    .where("last_activity_at > ?", 30.minutes.ago)
    .order(last_activity_at: :desc)

  if device_fingerprint.present?
    scope.where(device_fingerprint: device_fingerprint).first || scope.first
  else
    scope.first
  end
end
```

Priority order:
1. **Fingerprint + visitor_id** match (strongest signal, unchanged behavior)
2. **Visitor_id only** match (fallback for fingerprint instability)

The `new_traffic_source?` gate still applies — if the request has UTM params, click_ids, or an external referrer, a new session is created regardless.

### Safety

- Visitor_id is per-domain (cookie doesn't cross domains), so no cross-visitor pollution
- The 30-minute sliding window prevents stale session reuse
- `new_traffic_source?` still forces new sessions for genuine new traffic
- `ended_at: nil` check prevents reusing explicitly closed sessions

---

## Data Repair (Completed)

24h post-deploy data was repaired in production console (2026-02-11):
- 43 conversions reassigned to correct sessions
- 65 events moved from self-referral sessions to correct sessions
- 3,025 attribution credits recalculated via `ReattributionService`
- 43 empty ghost sessions deleted

Verification confirmed 0 referral conversions remaining in the 24h window.

---

## Key Files

| File | Change |
|------|--------|
| `app/services/sessions/creation_service.rb` | `find_active_visitor_session` visitor_id fallback |
| `test/services/sessions/creation_service_test.rb` | New tests for fingerprint fallback behavior |
