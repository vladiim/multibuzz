# Funnel Filtering Specification

**Status**: Draft
**Created**: 2025-12-02
**Epic**: E1S3 - Dashboard

---

## Problem Statement

The current funnel implementation shows ALL event types ordered by count. This creates issues:

1. **No logical grouping**: Events from different user journeys are mixed together
2. **Confusing metrics**: A "signup" funnel mixes with "purchase" funnel events
3. **No way to focus**: Users can't analyze a specific conversion path

**Example of current behavior**:
```
All events ordered by count:
1. page_view       - 10,000 users
2. add_to_cart     -  2,500 users  (purchase funnel)
3. signup_start    -  2,000 users  (signup funnel)
4. pricing_click   -  1,500 users  (signup funnel)
5. checkout        -  1,200 users  (purchase funnel)
6. signup_complete -    800 users  (signup funnel)
7. purchase        -    500 users  (purchase funnel)
```

This mixes two different funnels, making conversion rate analysis meaningless.

---

## Solution

### 1. Add `funnel` attribute to events

Events can optionally be tagged with a funnel name:

```ruby
# SDK usage
Multibuzz.track(
  event_type: "signup_start",
  funnel: "signup",           # Optional funnel tag
  properties: { ... }
)

Multibuzz.track(
  event_type: "add_to_cart",
  funnel: "purchase",         # Different funnel
  properties: { ... }
)

Multibuzz.track(
  event_type: "page_view",
  # No funnel tag - appears in "All" view only
  properties: { ... }
)
```

### 2. Add funnel dropdown filter to dashboard

```
┌─────────────────────────────────────────────────────────────┐
│ [All Funnels ▼] Conversion Funnel                           │
│  ├─ All Funnels (default)                                   │
│  ├─ signup                                                  │
│  └─ purchase                                                │
└─────────────────────────────────────────────────────────────┘
```

**Behavior**:
- **"All Funnels"** (default): Shows all events regardless of funnel tag
- **Specific funnel**: Shows only events tagged with that funnel name

---

## Data Model

### Events Table

```ruby
# Migration: add_funnel_to_events
add_column :events, :funnel, :string
add_index :events, [:account_id, :funnel], name: "index_events_on_account_funnel"
```

**Column details**:
| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| funnel | string | YES | NULL | Funnel identifier (e.g., "signup", "purchase") |

**Constraints**:
- Nullable (events without funnel appear in "All" view only)
- No foreign key (funnels are defined implicitly by usage)
- Max length: 255 characters (standard string)

---

## API Contract

### Event Ingestion

Update the event ingestion API to accept `funnel` parameter:

```json
POST /api/v1/events
{
  "events": [
    {
      "event_type": "signup_start",
      "funnel": "signup",
      "visitor_id": "vis_abc123",
      "session_id": "sess_xyz789",
      "timestamp": "2025-12-02T10:30:00Z",
      "properties": { "source": "homepage" }
    }
  ]
}
```

**Validation**:
- `funnel`: Optional string, max 255 chars, alphanumeric + underscore only
- Invalid funnel values are rejected with 422 error

### Conversion Tracking

Update conversion API to accept `funnel` parameter:

```json
POST /api/v1/conversions
{
  "conversion_type": "signup",
  "funnel": "signup",
  "revenue": 0,
  "visitor_id": "vis_abc123"
}
```

---

## Dashboard Behavior

### Funnel Dropdown

**Location**: Top of Funnel tab, left side

**States**:
1. **No funnels defined**: Dropdown hidden, shows all events
2. **Funnels exist**: Dropdown visible with options

**Options**:
- "All Funnels" (default) - shows all events
- List of unique funnel names from account's events

### Filtering Logic

```ruby
# When funnel filter is "All" or nil
scope = account.events.where(...)  # No funnel filter

# When specific funnel selected
scope = account.events.where(funnel: "signup").where(...)
```

### Available Funnels Query

```ruby
# Returns unique funnel names for account
account.events
  .where.not(funnel: nil)
  .distinct
  .pluck(:funnel)
  .sort

# Returns: ["purchase", "signup"]
```

---

## Implementation Checklist

### Phase 1: Data Model
- [x] Create migration to add `funnel` column to events
- [x] Add index on `[account_id, funnel]`
- [x] Run migration
- [ ] Update Event model (no validation needed - nullable string)

### Phase 2: API Updates
- [ ] Update `Events::IngestionService` to accept `funnel` param
- [ ] Update `Conversions::TrackingService` to accept `funnel` param
- [ ] Add validation for funnel format (alphanumeric + underscore)
- [ ] Update API documentation

### Phase 3: Dashboard Service Layer
- [ ] Update `Dashboard::Scopes::EventsScope` to filter by funnel
- [ ] Update `Dashboard::FunnelDataService` to:
  - [ ] Accept `funnel` filter param
  - [ ] Return `available_funnels` in response
  - [ ] Include funnel in cache key
- [ ] Update `Dashboard::Queries::FunnelStagesQuery` (no changes needed - uses scope)

### Phase 4: Dashboard UI
- [ ] Add funnel dropdown to Funnel tab header
- [ ] Create Stimulus controller for funnel selection
- [ ] Update URL params to include `funnel` filter
- [ ] Handle empty state (no funnels defined)

### Phase 5: Testing
- [x] Unit tests for EventsScope funnel filtering (9 tests)
- [x] Unit tests for FunnelDataService with funnel param (6 tests)
- [x] Unit tests for available_funnels query (included above)
- [ ] Integration tests for API ingestion with funnel
- [ ] System tests for dashboard funnel dropdown

---

## Test Cases

### Unit: EventsScope

```ruby
test "filters events by funnel when funnel param provided"
test "returns all events when funnel is nil"
test "returns all events when funnel is 'all'"
test "excludes events from other funnels"
test "includes events with nil funnel only in 'all' view"
```

### Unit: FunnelDataService

```ruby
test "returns stages filtered by funnel"
test "returns available_funnels list"
test "available_funnels excludes nil values"
test "available_funnels sorted alphabetically"
test "cache key includes funnel param"
```

### Unit: Event Ingestion

```ruby
test "accepts funnel param in event data"
test "saves funnel to event record"
test "allows nil funnel"
test "rejects invalid funnel format"
```

---

## Edge Cases

1. **No events with funnels**: Dropdown hidden, shows all events
2. **Mixed events**: Some with funnel, some without
   - "All" shows everything
   - Specific funnel shows only tagged events
3. **Funnel with no events in date range**: Shows empty funnel
4. **Case sensitivity**: Funnel names are case-sensitive ("Signup" != "signup")

---

## Future Enhancements (Out of Scope)

1. **Funnel definition UI**: Let users define funnel steps in order
2. **Funnel templates**: Pre-built funnels (e-commerce, SaaS signup, etc.)
3. **Cross-funnel analysis**: Compare conversion rates across funnels
4. **Funnel alerts**: Notify when conversion rate drops

---

## References

- `lib/specs/dashboard_spec.md` - Dashboard specification
- `lib/docs/architecture/conversion_funnel_analysis.md` - Funnel analysis concepts
- `app/services/dashboard/funnel_data_service.rb` - Current implementation
