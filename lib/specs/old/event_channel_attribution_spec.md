# Event Channel Attribution Fix

**Date:** 2026-02-25
**Priority:** P0
**Status:** Complete
**Branch:** `feature/session-bot-detection`

---

## Summary

Events in the funnel chart showed 99% "Direct" regardless of the session's actual marketing channel. The root cause was `Events::ProcessingService#capture_utm_if_new_session` which overwrote the session's correctly-attributed channel with "direct" the first time an event was processed. Sessions attributed by referrer or click IDs (organic search, paid search via gclid, social, referral, video, AI) had `initial_utm: {}`, which Rails considers `blank?`, triggering the overwrite with degraded context that fell through to direct.

**Server-side fix only. No SDK changes required.**

---

## Root Cause

`Events::ProcessingService#capture_utm_if_new_session` used `session.initial_utm.blank?` as its guard clause. Sessions attributed by referrer or click IDs (not UTM params) have `initial_utm: {}` (empty hash). `{}.blank?` returns `true` in Rails, so the guard failed to protect. The method then recomputed channel with only 2 of 5 required parameters (missing `click_ids`, `page_host`, `account_domains`), falling through to `Channels::DIRECT`.

### Data flow (before fix)

```
1. POST /sessions → CreationService
   → ChannelAttributionService(utm, referrer, click_ids, page_host, account_domains)
   → session.channel = "organic_search"  ← CORRECT
   → session.initial_utm = {}            ← empty (no UTM params in URL)

2. POST /events (add_to_cart) → ProcessingService
   → capture_utm_if_new_session
     → session.initial_utm.blank?        ← {}.blank? == true!
     → ChannelAttributionService(empty_utm, nil_referrer)
     → session.channel = "direct"        ← OVERWRITTEN, WRONG
```

### Evidence

From production funnel (2026-02-25, pre-fix):
- **Visits:** 81,589 — healthy channel mix
- **Add to Cart:** 3,050 — 3,031 Direct (99.4%), 16 Paid Search, 3 Organic Search

The 19 non-direct events corresponded to sessions with explicit UTM params, making `initial_utm` non-blank.

---

## Fix Applied

### Change 1: Guard clause (`app/services/events/processing_service.rb`)

```ruby
# BEFORE
def capture_utm_if_new_session
  return unless session.initial_utm.blank?
  ...
end

# AFTER
def capture_utm_if_new_session
  return if session.channel.present?
  ...
end
```

### Change 2: Full attribution context (`app/services/events/processing_service.rb`)

```ruby
# BEFORE (2 params)
def channel
  @channel ||= Sessions::ChannelAttributionService.new(utm_data, referrer).call
end

# AFTER (5 params, matching CreationService)
def channel
  @channel ||= Sessions::ChannelAttributionService.new(
    utm_data, referrer, click_ids,
    page_host: page_host, account_domains: account_domains
  ).call
end
```

Added `click_ids`, `page_host`, `account_domains` helper methods to `ProcessingService`.

### Change 3: Backfill rake task (`lib/tasks/attribution.rake`)

`attribution:fix_event_channel_overwrite` — targeted task for sessions with `channel = "direct"` that still had `click_ids` or `initial_referrer` intact. Also fixed existing `attribution:backfill_channels` to include `account_domains`.

### Backfill results (production, account 2)

```
Found 132,065 potentially corrupted sessions
Fixed: 89
Unchanged (legitimately direct): 131,976

Recovered channels:
  organic_search: 38
  paid_search: 33
  referral: 17
  paid_social: 1
```

Most sessions had `initial_referrer` clobbered to nil by the bug (the overwrite set `initial_referrer: referrer` where the event's referrer was nil). Only sessions with preserved `click_ids` or non-nil `initial_referrer` were recoverable.

---

## Verification (post-deploy)

Checked post-fix sessions with events in production (3 hours after deploy):

```
POST-FIX SESSIONS WITH EVENTS (49):
  direct: 26 (53.1%)
  referral: 23 (46.9%)

Spot check — referral sessions after events processed:
  channel: referral | utm: {} | ref: "https://petresortsaustralia.com.au/search"
  channel: referral | utm: {} | ref: "https://stage.petresorts.io/search"
```

Sessions with `utm: {}` and a referrer correctly retain their channel after event processing. Before the fix, all would have been overwritten to "direct".

---

## Tests

6 tests added to `test/services/events/processing_service_test.rb`:

| Test | Verifies |
|------|----------|
| should not overwrite session channel when initial_utm is empty hash | Guard protects referrer-attributed sessions |
| should not overwrite session channel attributed by click IDs | Guard protects click-ID-attributed sessions |
| should set channel with full context when session has no channel | TrackingService path gets 5-param attribution (gclid → paid_search) |
| should set channel from referrer when session has no channel | TrackingService path classifies referrer correctly |
| should set channel as direct when session has no channel and no signals | Genuinely direct traffic still works |
| second event should not change channel set by first event | Multi-event sessions protected |

Full suite: 2,603 tests, 0 failures.

---

## Files Changed

| File | Change |
|------|--------|
| `app/services/events/processing_service.rb` | Guard clause fix + full attribution context + helper methods |
| `lib/tasks/attribution.rake` | Targeted backfill task + `account_domains` fix on existing task |
| `test/services/events/processing_service_test.rb` | 6 new channel attribution tests |
