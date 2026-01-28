# Unified Events Feed

**Date:** 2026-01-29
**Status:** Complete
**Branch:** `feature/e1s4-content`

---

## Problem

The Events tab only shows records from the `events` table -- custom events tracked via `POST /api/v1/events`. Conversions, identifications, session starts, and visitor creation all happen silently in separate tables. A developer debugging their integration has no single place to see the full picture of what's happening.

Today's Events tab shows `add_to_cart`, `page_view`, `signup` etc. but a conversion tracked via `POST /api/v1/conversions` never appears. Neither does an `identify` call or a new session. The feed tells a partial story.

---

## Solution

Introduce a unified activity feed that merges records from multiple tables into a single chronological stream. Each activity type gets a distinct visual treatment (icon, color, label) so the feed reads like a timeline of everything Multibuzz knows about.

### Activity Types

| Type | Source Table | Badge | Color | Label | Primary Info |
|------|-------------|-------|-------|-------|-------------|
| Custom Event | `events` | `A` (first letter of type) | Indigo | `add_to_cart`, `signup`, etc. | URL / page path |
| Conversion | `conversions` | `$` | Green | `conversion: {type}` | Revenue (if present), conversion type |
| Identify | `identities` | `ID` | Purple | `identify` | `external_id`, traits summary |
| Session Start | `sessions` | `S` | Blue | `session_started` | Referrer, UTM source, channel |
| Visitor Created | `visitors` | `V` | Gray | `visitor_created` | Visitor ID (truncated) |

### Data Flow (Proposed)

```
DashboardController#show
  |
  UnifiedFeed::QueryService.new(account, limit:, test_only:)
    |
    +-- account.events       --> { type: :event, occurred_at:, record: }
    +-- account.conversions  --> { type: :conversion, occurred_at: converted_at, record: }
    +-- account.identities   --> { type: :identify, occurred_at: last_identified_at, record: }
    +-- account.sessions     --> { type: :session, occurred_at: started_at, record: }
    +-- account.visitors     --> { type: :visitor, occurred_at: created_at, record: }
    |
    Sort all by timestamp DESC, take limit
    |
    Return array of FeedItem structs
```

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Query strategy | Union in Ruby, not SQL UNION | Tables have different schemas and composite keys (events uses `[id, occurred_at]`). Ruby merge is simpler and the dataset is small (100 records). |
| New model? | No -- use a `FeedItem` Struct | Lightweight, no persistence needed. Just a presentation wrapper. |
| Test mode filtering | Apply `is_test` to events and conversions; show all sessions/visitors/identities | Sessions and visitors don't have `is_test`. Identities don't either. Only filter what has the flag. |
| Broadcast | Keep existing event broadcast; add broadcasts for conversions | Sessions/visitors/identities are high-volume internals -- broadcasting every one would be noisy. Conversions are high-signal. |
| Pagination | Keep `limit: 100` with "load more" deferred | Same as current. Unified feed doesn't change pagination strategy. |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path | Mix of events, conversions, sessions | Interleaved chronologically with distinct badges |
| Events only | No conversions/identities tracked yet | Looks identical to current Events tab |
| Conversion without event | Conversion tracked directly (no triggering event) | Shows as standalone conversion entry |
| Identify call | `POST /api/v1/identify` | Shows identify entry with external_id and traits |
| New visitor + session | First visit | Two entries: visitor_created then session_started |
| Test mode on | `test_only=true` | Only test events and test conversions shown; sessions/visitors/identities still shown (they lack `is_test`) |
| Empty account | No data at all | Empty state message (existing behavior) |
| High volume | Many sessions/visitors | Feed stays useful because limit caps at 100 most recent |

---

## Implementation Tasks

### Phase 1: Query Service + FeedItem

- [x] **1.1** Create `FeedItem` struct in `app/models/feed_item.rb`
- [x] **1.2** Create `UnifiedFeed::QueryService` in `app/services/unified_feed/query_service.rb`
- [x] **1.3** Write tests for `UnifiedFeed::QueryService` (12 tests, 46 assertions)

### Phase 2: View Updates

- [x] **2.1** Update `DashboardController#show` to use `UnifiedFeed::QueryService`
- [x] **2.2** Create `_feed_item.html.erb` dispatcher partial
- [x] **2.3** Create type-specific partials (event, conversion, identify, session, visitor)
- [x] **2.4** Update `LiveEventsHelper` with badge helpers and JSON serializers for each type
- [x] **2.5** Update event panel title to generic "Details"

### Phase 3: Real-time Broadcasts

- [x] **3.1** Add `broadcast_to_feed` callback to `Conversion::Callbacks`
- [x] **3.2** Update `Event::Broadcasts` to use `feed_item` partial

---

## Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/services/unified_feed/query_service.rb` | New -- merges activity streams | Create |
| `app/models/feed_item.rb` | New -- lightweight struct | Create |
| `app/controllers/dashboard_controller.rb` | Load unified feed | Replace `load_live_events` |
| `app/views/dashboard/live_events/_feed_item.html.erb` | New -- dispatch partial | Create |
| `app/views/dashboard/live_events/_conversion_card.html.erb` | New -- conversion display | Create |
| `app/views/dashboard/live_events/_identify_card.html.erb` | New -- identify display | Create |
| `app/views/dashboard/live_events/_session_card.html.erb` | New -- session display | Create |
| `app/views/dashboard/live_events/_visitor_card.html.erb` | New -- visitor display | Create |
| `app/helpers/live_events_helper.rb` | Badge helpers per type | Update |
| `app/models/concerns/conversion/broadcasts.rb` | New -- real-time conversion broadcast | Create |
| `app/views/dashboard/live_events/_event_card.html.erb` | Existing event card | Minor refactor |

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Query service returns mixed types | `test/services/unified_feed/query_service_test.rb` | Chronological ordering across tables |
| Test mode filters events + conversions | `test/services/unified_feed/query_service_test.rb` | `is_test` filtering applied correctly |
| Account isolation | `test/services/unified_feed/query_service_test.rb` | No cross-tenant data leakage |
| Limit respected | `test/services/unified_feed/query_service_test.rb` | Returns at most `limit` items |
| Empty account | `test/services/unified_feed/query_service_test.rb` | Returns `[]` |

### Manual QA

1. Track events, conversions, and identify calls via test SDK
2. Open Events tab -- verify all types appear interleaved by time
3. Toggle "Test events only" -- verify filtering
4. Click each activity type -- verify panel shows correct details
5. Track a new conversion -- verify it appears in real-time

---

## Definition of Done

- [ ] All activity types (event, conversion, identify, session, visitor) appear in Events tab
- [ ] Each type has distinct visual treatment (badge, color, label)
- [ ] Chronological ordering is correct across all types
- [ ] Test mode filter works for events and conversions
- [ ] Click-to-detail panel works for all types
- [ ] Conversions broadcast in real-time
- [ ] Tests pass (unit + integration)
- [ ] No regressions in existing Events tab behavior
- [ ] Spec updated with final state

---

## Out of Scope

- Filtering by activity type (e.g., "show only conversions") -- future enhancement
- Pagination / infinite scroll -- keep existing `limit: 100`
- Broadcasting session/visitor creation in real-time -- too noisy
- Search within the feed
- Exporting unified feed data
