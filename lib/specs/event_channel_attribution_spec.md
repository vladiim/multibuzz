# Event Channel Attribution Fix

**Date:** 2026-02-25
**Priority:** P0
**Status:** Draft
**Branch:** `feature/event-channel-attribution`

---

## Summary

Events in the funnel chart show 99% "Direct" regardless of the session's actual marketing channel. The root cause is `Events::ProcessingService#capture_utm_if_new_session` which overwrites the session's correctly-attributed channel with "direct" the first time an event is processed. Sessions attributed by referrer or click IDs (organic search, paid search via gclid, social, referral, video, AI) have `initial_utm: {}`, which Rails considers `blank?`, triggering the overwrite with degraded context that falls through to direct.

**Server-side fix only. No SDK changes required.** SDKs are sending correct data — the server is clobbering it.

---

## Current State

### How sessions get correct channels

`Sessions::CreationService` (lines 267-275) computes channel with full context:

```ruby
# app/services/sessions/creation_service.rb:267
def channel
  @channel ||= Sessions::ChannelAttributionService.new(
    normalized_utm,
    referrer,
    click_ids,
    page_host: page_host,
    account_domains: account_domains
  ).call
end
```

Five signals: UTM params, referrer, click IDs (gclid/fbclid), page host (for self-referral), account domains. This works correctly. The Visits stage in the funnel shows a healthy channel distribution.

### How events destroy those channels

`Events::ProcessingService#capture_utm_if_new_session` (lines 119-127) runs for every event:

```ruby
# app/services/events/processing_service.rb:119
def capture_utm_if_new_session
  return unless session.initial_utm.blank?

  session.update(
    initial_utm: utm_data,
    initial_referrer: referrer,
    channel: channel
  )
end
```

The guard `session.initial_utm.blank?` fails to protect because:

1. Sessions attributed by referrer or click IDs (not UTM params) have `initial_utm: {}` (empty hash)
2. `{}.blank?` returns `true` in Rails
3. The guard passes, and `channel` is computed with degraded context (line 116):

```ruby
# app/services/events/processing_service.rb:115
def channel
  @channel ||= Sessions::ChannelAttributionService.new(utm_data, referrer).call
end
```

This is missing three critical parameters vs `CreationService`:

| Parameter | CreationService | ProcessingService | Impact |
|-----------|----------------|-------------------|--------|
| `click_ids` | `{gclid: "abc"}` | **missing** (defaults `{}`) | Paid search/social via gclid/fbclid misclassified |
| `page_host` | `"example.com"` | **missing** (defaults `nil`) | Internal referrer detection broken |
| `account_domains` | `["example.com"]` | **missing** (defaults `[]`) | Self-referral detection broken |

Without these, `ChannelAttributionService` falls through its entire hierarchy to the final fallback: `Channels::DIRECT`.

### Why conversions are less affected

`Conversions::TrackingService` does NOT call `capture_utm_if_new_session`. It only updates `last_activity_at`. The separate conversions dashboard uses `attribution_credits.channel` which is set from `sessions.channel` at attribution time. However, if a conversion's attribution runs AFTER event processing has already overwritten the session's channel, the credits will also be wrong.

### Data flow (current, broken)

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

3. Dashboard funnel query
   → events JOIN sessions ON sessions.channel
   → all events for this session show "direct"
```

### Evidence

From production funnel (2026-02-25):
- **Visits:** 81,589 — healthy channel mix (paid search, organic search, social, etc.)
- **Add to Cart:** 3,050 — 3,031 Direct (99.4%), 16 Paid Search, 3 Organic Search
- **Conversions:** 754

The 19 non-direct events (16 + 3) correspond to sessions that had explicit UTM params in the URL (e.g. `?utm_source=google&utm_medium=cpc`), making `initial_utm` non-blank and protecting the guard clause. Every other channel (organic search via referrer, paid search via gclid, social, referral, etc.) was overwritten to direct.

### Key files

| File | Role |
|------|------|
| `app/services/sessions/creation_service.rb` | Creates sessions with correct channel (5-param attribution) |
| `app/services/events/processing_service.rb` | Processes events, overwrites session channel (2-param attribution) |
| `app/services/sessions/tracking_service.rb` | Creates sessions from event path (no channel set) |
| `app/services/sessions/channel_attribution_service.rb` | Channel classification logic |
| `app/services/dashboard/queries/funnel_stages_query.rb` | Funnel chart query (JOINs events to sessions.channel) |

---

## Proposed Solution

### Core fix: stop overwriting correctly-attributed channels

Replace the `initial_utm.blank?` guard with a `channel.present?` guard. If the session already has a channel set by `CreationService`, never overwrite it. Only set UTM/channel/referrer when the session was just created by `TrackingService` (no prior `/sessions` call) and genuinely has no attribution.

When we do set the channel on the event path, use the full 5-parameter `ChannelAttributionService` call (matching `CreationService`) so that click IDs, referrer domain patterns, and self-referral detection all work correctly.

### Data flow (proposed, fixed)

```
1. POST /sessions → CreationService
   → session.channel = "organic_search"    ← CORRECT, unchanged

2. POST /events → ProcessingService
   → capture_utm_if_new_session
     → session.channel.present? → SKIP     ← guard protects
   → event saved, linked to session
   → session.channel still "organic_search" ← PRESERVED

3. POST /events (no prior /sessions call) → ProcessingService
   → TrackingService creates session (channel: nil)
   → capture_utm_if_new_session
     → session.channel.blank? → proceed
     → ChannelAttributionService(utm, referrer, click_ids, page_host, account_domains)
     → session.channel = computed_channel   ← FULL CONTEXT
```

### Change 1: Fix the guard clause

```ruby
# BEFORE (broken)
def capture_utm_if_new_session
  return unless session.initial_utm.blank?
  ...
end

# AFTER (fixed)
def capture_utm_if_new_session
  return if session.channel.present?
  ...
end
```

`channel.present?` is the correct guard because:
- Sessions from `CreationService` always have a channel → protected
- Sessions from `TrackingService` never have a channel → correctly identified as needing attribution
- No ambiguity from empty hashes

### Change 2: Full attribution context on event path

```ruby
# BEFORE (degraded — 2 params)
def channel
  @channel ||= Sessions::ChannelAttributionService.new(utm_data, referrer).call
end

# AFTER (full context — 5 params, matching CreationService)
def channel
  @channel ||= Sessions::ChannelAttributionService.new(
    utm_data,
    referrer,
    click_ids,
    page_host: page_host,
    account_domains: account_domains
  ).call
end
```

Add the missing helper methods to `ProcessingService`:

```ruby
def click_ids
  @click_ids ||= Sessions::ClickIdCaptureService.new(url: url).call
end

def page_host
  @page_host ||= begin
    URI.parse(url).host if url.present?
  rescue URI::InvalidURIError
    nil
  end
end

def account_domains
  @account_domains ||= account.sessions
    .where.not(landing_page_host: nil)
    .distinct
    .pluck(:landing_page_host)
end
```

### Change 3: Backfill corrupted sessions

One-time rake task to re-attribute sessions whose channel was overwritten. Target: sessions with `channel = "direct"` that have a non-nil `initial_referrer` or non-empty `click_ids`, which indicates they were originally attributed to a non-direct channel.

```ruby
# lib/tasks/backfill_session_channels.rake
desc "Re-attribute sessions whose channel was incorrectly overwritten to direct"
task backfill_session_channels: :environment do
  Account.find_each do |account|
    account_domains = account.sessions
      .where.not(landing_page_host: nil)
      .distinct.pluck(:landing_page_host)

    sessions = account.sessions.where(channel: "direct")
      .where("initial_referrer IS NOT NULL OR click_ids != '{}'::jsonb")

    sessions.find_each do |session|
      new_channel = Sessions::ChannelAttributionService.new(
        session.initial_utm || {},
        session.initial_referrer,
        session.click_ids || {},
        page_host: session.landing_page_host,
        account_domains: account_domains
      ).call

      session.update_column(:channel, new_channel) if new_channel != "direct"
    end
  end
end
```

---

## All States

| # | State | Condition | Expected Behaviour |
|---|-------|-----------|-------------------|
| 1 | Normal flow (UTM params) | Session created with `?utm_source=google&utm_medium=cpc` | `channel: "paid_search"`. Event arrives → guard `channel.present?` → skip. Preserved |
| 2 | Normal flow (referrer only) | Session created from Google search (no UTM) | `channel: "organic_search"`. Event arrives → guard `channel.present?` → skip. Preserved |
| 3 | Normal flow (click IDs only) | Session created with `?gclid=abc` (no UTM) | `channel: "paid_search"`. Event arrives → guard `channel.present?` → skip. Preserved |
| 4 | Event-first (no prior session) | Event arrives before POST /sessions | TrackingService creates session (channel: nil). `channel.present?` → false → set channel with full context |
| 5 | Event-first with UTM in URL | Event carries URL with `?utm_source=newsletter` | TrackingService creates session (channel: nil). Attribution runs with UTM → `channel: "email"` |
| 6 | Event-first with referrer | Event carries referrer `google.com` | TrackingService creates session (channel: nil). Attribution runs with referrer → `channel: "organic_search"` |
| 7 | Event-first, no signals | Event with no URL, no referrer, no click IDs | TrackingService creates session (channel: nil). Attribution → `channel: "direct"`. Correct |
| 8 | Multiple events, same session | Second event arrives for already-attributed session | Guard `channel.present?` → skip. No overwrites |
| 9 | Backfill: corrupted session | `channel: "direct"`, `initial_referrer: "google.com"` | Rake task re-attributes → `channel: "organic_search"` |
| 10 | Backfill: legitimately direct | `channel: "direct"`, `initial_referrer: nil`, `click_ids: {}` | Rake task skips — no signals to re-evaluate |
| 11 | Cross-account isolation | Events for account A | `account_domains` scoped to event's account |

---

## Implementation Tasks

### Phase 1: Fix the overwrite bug

- [ ] **1.1** Fix guard clause in `ProcessingService#capture_utm_if_new_session`: `session.initial_utm.blank?` → `session.channel.blank?`
- [ ] **1.2** Add `click_ids`, `page_host`, `account_domains` helpers to `ProcessingService`
- [ ] **1.3** Update `#channel` to pass all 5 parameters to `ChannelAttributionService`
- [ ] **1.4** Write tests (states 1-8)

### Phase 2: Backfill corrupted data

- [ ] **2.1** Write rake task `backfill_session_channels`
- [ ] **2.2** Run backfill on production
- [ ] **2.3** Verify funnel chart shows correct channel distribution for events

### Phase 3: Verify downstream

- [ ] **3.1** Verify attribution credits for conversions whose sessions were backfilled
- [ ] **3.2** Re-attribute affected conversions if needed
- [ ] **3.3** Full test suite — no regressions

---

## Testing Strategy

### Unit Tests

| # | Test | File | Verifies |
|---|------|------|----------|
| 1 | Event for session with channel set → channel not overwritten | `test/services/events/processing_service_test.rb` | Guard clause protects existing channel |
| 2 | Event for session with `initial_utm: {}` and `channel: "organic_search"` → channel preserved | `test/services/events/processing_service_test.rb` | Empty UTM no longer triggers overwrite |
| 3 | Event for session with no channel (TrackingService path) → channel computed with full context | `test/services/events/processing_service_test.rb` | Falls through to full attribution |
| 4 | Event with click IDs for channelless session → paid_search | `test/services/events/processing_service_test.rb` | Click IDs passed to ChannelAttributionService |
| 5 | Event with referrer for channelless session → correct channel | `test/services/events/processing_service_test.rb` | Referrer + page_host + account_domains all used |
| 6 | Event with no signals for channelless session → direct | `test/services/events/processing_service_test.rb` | Genuinely direct traffic still classified correctly |
| 7 | Multiple events same session → no channel change | `test/services/events/processing_service_test.rb` | Second event skips attribution |
| 8 | Cross-account isolation | `test/services/events/processing_service_test.rb` | `account_domains` scoped correctly |

### Manual QA

1. Deploy to staging
2. Create test sessions: organic search referrer, gclid, fbclid, UTM params, direct
3. Track events against each session
4. Open funnel → verify events show correct channels
5. Compare Visits vs Events channel distribution — should match proportionally

---

## Definition of Done

- [ ] `Events::ProcessingService` never overwrites a session that already has a channel
- [ ] Event-path attribution uses full context (5 params matching `CreationService`)
- [ ] Funnel chart shows correct channel distribution for events
- [ ] Corrupted production sessions backfilled
- [ ] All tests pass, zero regressions
- [ ] All queries scoped to account

---

## Out of Scope

- **SDK changes** — not needed. SDKs send correct data, server-side fix only
- **Denormalizing channel onto events table** — events correctly derive channel from session JOIN. Fix the source data
- **Changing funnel query to use attribution_credits for events** — unnecessary complexity
- **Removing `capture_utm_if_new_session` entirely** — still needed for the TrackingService path (events without prior session call)
- **Blanket re-attribution of all historical conversions** — only re-attribute from the affected window if needed
