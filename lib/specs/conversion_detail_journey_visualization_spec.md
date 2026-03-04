# Conversion Detail & Journey Visualization Specification

**Date:** 2026-03-05
**Priority:** P1
**Status:** Draft
**Branch:** `feature/conversion-detail-journey`

---

## Summary

Add the ability to drill into individual conversions from the dashboard, see their full data, and visualise the customer journey that led to conversion. When a conversion is linked to an identity, clicking through reveals a rich identity profile with channel history, conversion timeline, and a computed engagement score. This is a visual differentiator — no attribution tool today shows the journey this clearly.

---

## Problem

The conversions dashboard shows aggregated KPIs and channel charts. Marketers can see *totals* but can't inspect *individual conversions* — which visitor, what journey, how long between touchpoints, which channels contributed. They can't answer:

- "Show me the journey for this $500 purchase"
- "How did this lead find us? What channels touched them before converting?"
- "What does this identified user's full engagement history look like?"

All the data exists — `journey_session_ids`, `attribution_credits`, `identity` links — it's just not exposed.

---

## Current State

### What exists

| Component | File | What it does |
|-----------|------|--------------|
| Conversion model | `app/models/conversion.rb` | Stores `journey_session_ids`, `identity_id`, `conversion_type`, `revenue`, `properties` |
| Journey builder | `app/services/attribution/journey_builder.rb` | Builds touchpoint array `[{session_id, channel, occurred_at}]` from visitor sessions |
| Attribution credits | `app/models/attribution_credit.rb` | Per-model credit allocation with channel, UTM data, revenue split |
| Identity model | `app/models/identity.rb` | `external_id`, `traits` JSONB, links to visitors and conversions |
| Dashboard | `app/controllers/dashboard/conversions_controller.rb` | Aggregated KPIs, time series, channel breakdown — no individual conversion view |
| Event panel | `app/javascript/controllers/event_panel_controller.js` | Slide-out panel pattern (reusable for detail views) |
| Unified feed | `app/services/unified_feed/query_service.rb` | Shows conversions as cards in live feed — no drill-in |

### Data flow (current)

```
Conversion created
    → AttributionCalculationService
    → journey_session_ids populated (array of session IDs)
    → AttributionCredits created (channel, credit, revenue_credit, UTM)
    → Dashboard shows aggregated totals
    → No way to inspect individual conversion or journey
```

---

## Proposed Solution

Three interconnected views, all server-rendered with Turbo Frames:

### 1. Conversions Table

A paginated table of individual conversions, accessible from a new "Conversions" tab or link on the dashboard. Each row shows key data at a glance.

**Columns:**

| Column | Source |
|--------|--------|
| Date | `conversion.converted_at` |
| Type | `conversion.conversion_type` |
| Revenue | `conversion.revenue` + `conversion.currency` |
| Channels | Distinct channels from `journey_session_ids` sessions (badges) |
| Touchpoints | `journey_session_ids.length` |
| Time to convert | First journey session `started_at` → `converted_at` |
| Identity | `conversion.identity.external_id` or "Anonymous" |

**Interactions:**
- Click row → opens Conversion Detail view
- Click identity badge → opens Identity Detail view
- Filter by conversion_type, date range, channel, identity status (identified/anonymous)
- Sort by date (default desc), revenue, time to convert
- Paginate (25 per page)

### 2. Conversion Detail + Journey Visualisation

A dedicated page (not a panel — too much content for a slide-out) showing the full conversion record and a visual journey timeline.

**Conversion data section** (card with key-value pairs):

| Field | Source |
|-------|--------|
| Conversion ID | `conversion.prefix_id` (`conv_...`) |
| Type | `conversion.conversion_type` |
| Revenue | `conversion.revenue` formatted with `conversion.currency` |
| Date | `conversion.converted_at` formatted |
| Funnel | `conversion.funnel` (if present) |
| Acquisition | `conversion.is_acquisition` badge |
| Identity | Link to identity detail (or "Anonymous") |
| Visitor | `conversion.visitor.prefix_id` |
| Properties | `conversion.properties` rendered as key-value table |

**Attribution credits section** (table):

| Model | Channel | Credit | Revenue | UTM Source | UTM Campaign |
|-------|---------|--------|---------|------------|--------------|

**Journey visualisation** (the differentiator):

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│  Paid Search │──3 d───▶│ Paid Social  │──2 d───▶│Organic Search│──0 d───▶│ ✓ Converted  │
│  Google Ads  │         │  Instagram   │         │   google     │         │  Purchase    │
│  Mar 1, 2026 │         │  Mar 4, 2026 │         │  Mar 6, 2026 │         │  Mar 6, 2026 │
│  /landing    │         │  /pricing    │         │  /features   │         │  $249.00     │
└─────────────┘         └─────────────┘         └─────────────┘         └─────────────┘
```

Each journey node shows:
- Channel name (with channel colour/icon)
- Source (from session `initial_utm.source` or referrer)
- Date (`session.started_at`)
- Landing page (`session.landing_page_host` + first event path)
- Time gap to next node (edge label)

The final node is the conversion itself.

**Implementation:** Server-rendered HTML with Tailwind. Horizontal flow on desktop, vertical stack on mobile. Connected by lines/arrows with time-gap labels. Each session node is a `<div>` with channel-coloured left border. No JS charting library needed.

### 3. Identity Detail View

A dedicated page showing a full identity profile.

**Profile header:**
- External ID (`identity.external_id`)
- First/last identified dates
- Engagement score (computed, see below)

**Traits section:**
- Key-value rendering of `identity.traits` JSONB

**Channels section:**
- Aggregated channel breakdown across all sessions from all linked visitors
- Bar chart or badge list showing channel distribution

**Conversions section:**
- Table of all conversions linked to this identity
- Same columns as the conversions table (type, revenue, date, channels, time to convert)
- Click through to conversion detail

**Visitors section:**
- List of linked visitors with `visitor_id`, `first_seen_at`, `last_seen_at`, session count
- Shows cross-device picture

**Engagement Score:**

A computed score (not stored) providing a quick read on identity quality. Calculated on render from existing data:

| Signal | Weight | Calculation |
|--------|--------|-------------|
| Recency | 25% | Days since `last_identified_at` → decayed score (1.0 if today, 0.0 if 90+ days) |
| Frequency | 25% | Total session count across all visitors → normalised (cap at 20 sessions = 1.0) |
| Monetary | 25% | Total conversion revenue → normalised (cap at account's p95 revenue = 1.0) |
| Breadth | 25% | Distinct channels across all sessions → normalised (cap at 5 channels = 1.0) |

Score = weighted sum × 100, displayed as 0-100 with tier labels:
- 80-100: "Hot" (red badge)
- 60-79: "Warm" (orange badge)
- 40-59: "Engaged" (yellow badge)
- 20-39: "Cool" (blue badge)
- 0-19: "Cold" (grey badge)

This is intentionally simple and computed on the fly. No new DB columns. Can evolve later into a stored/configurable scoring model.

---

### Data Flow (Proposed)

```
Dashboard Conversions Table
    → click row → GET /dashboard/conversions/:prefix_id
    → Conversion::DetailQuery loads conversion + journey sessions + credits
    → Journey sessions loaded via journey_session_ids array
    → Rendered as timeline nodes with time gaps
    → Click identity link → GET /dashboard/identities/:prefix_id
    → Identity::DetailQuery loads identity + visitors + sessions + conversions
    → Engagement score computed on render
```

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Conversion detail as page vs panel | **Page** | Journey visualisation needs horizontal space; properties table can be large; URL-addressable for sharing |
| Journey rendering | **Server-rendered HTML** | Tailwind can handle the visual; no chart library overhead; works with Turbo navigation; accessible |
| Engagement score storage | **Computed on render** | Avoids schema changes, background jobs, staleness. Identity detail is low-traffic (inspecting individual records). Can materialise later if needed |
| Conversions table location | **New route under dashboard** | Keeps existing aggregated dashboard intact; conversions table is a different mental model (individual records vs aggregated metrics) |
| Identity detail as page vs modal | **Page** | Rich content (traits, conversions table, channel chart, visitors list) — too much for a modal |
| Engagement score formula | **Equal-weight RFMB** | Simple, transparent, no ML. Recency/Frequency/Monetary is proven (RFM). Added Breadth for multi-channel signal. Weights can be tuned later |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| **Happy path** | Conversion with journey + identity | Full detail, journey vis, identity link |
| **No journey** | `journey_session_ids` empty | Show conversion data + credits, journey section shows "No journey data — attribution may still be processing" |
| **Single touchpoint** | `journey_session_ids.length == 1` | Show single node → conversion (no time gap) |
| **Anonymous** | `identity_id` nil | Identity field shows "Anonymous visitor" — no link |
| **No revenue** | `revenue` nil | Revenue shows "—", engagement score monetary component = 0 |
| **No properties** | `properties` empty hash | Properties section hidden |
| **No traits** | `identity.traits` empty hash | Traits section shows "No traits collected" |
| **Cross-device** | Identity has multiple visitors | Visitors section shows all linked visitors; journey may span devices |
| **Many touchpoints** | 20+ sessions in journey | Horizontal scroll on desktop, vertical stack on mobile; consider "show all" toggle beyond 10 |
| **Conversion not found** | Invalid prefix_id | 404 page |
| **Wrong account** | Conversion belongs to different account | 404 (multi-tenancy: never leak existence) |
| **Test data** | `is_test: true` | Shown with "Test" badge; respects existing test/production filter |
| **Identity with no conversions** | Identity exists but zero conversions | Conversions section shows empty state; engagement monetary score = 0 |

---

## Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `config/routes.rb` | Dashboard routes | Add `resources :conversions, only: [:index, :show]` and `resources :identities, only: [:show]` under dashboard namespace |
| `app/controllers/dashboard/conversions_controller.rb` | Existing controller | Add `index` and `show` actions (existing `show` becomes the aggregated dashboard — rename to e.g. `overview` or keep with routing) |
| `app/controllers/dashboard/identities_controller.rb` | **New** | `show` action loading identity detail |
| `app/services/dashboard/conversion_detail_query.rb` | **New** query object | Loads conversion with eager-loaded journey sessions, credits, identity |
| `app/services/dashboard/identity_detail_query.rb` | **New** query object | Loads identity with visitors, sessions, conversions, computes engagement score |
| `app/services/dashboard/engagement_score_calculator.rb` | **New** service | Computes RFMB score for an identity |
| `app/views/dashboard/conversions/index.html.erb` | **New** | Conversions table with pagination |
| `app/views/dashboard/conversions/_conversion_row.html.erb` | **New** partial | Single row in conversions table |
| `app/views/dashboard/conversion_detail/show.html.erb` | **New** | Conversion detail page with journey vis |
| `app/views/dashboard/conversion_detail/_journey.html.erb` | **New** partial | Journey timeline visualisation |
| `app/views/dashboard/conversion_detail/_attribution_credits.html.erb` | **New** partial | Attribution credits table |
| `app/views/dashboard/conversion_detail/_properties.html.erb` | **New** partial | Properties key-value display |
| `app/views/dashboard/identities/show.html.erb` | **New** | Identity detail page |
| `app/views/dashboard/identities/_engagement_score.html.erb` | **New** partial | Score badge + breakdown |
| `app/views/dashboard/identities/_channel_breakdown.html.erb` | **New** partial | Channel distribution display |

---

## Implementation Tasks

### Phase 1: Conversions Table

- [ ] **1.1** Add routes: `GET /dashboard/conversions` (index) and `GET /dashboard/conversions/:id` (show — detail page, using prefix_id)
- [ ] **1.2** Create `Dashboard::ConversionDetailQuery` — loads conversion scoped to account with journey sessions (ordered), attribution credits, identity, visitor
- [ ] **1.3** Add `index` action to `Dashboard::ConversionsController` — paginated, filterable, sortable list of conversions
- [ ] **1.4** Build conversions table view (`index.html.erb` + `_conversion_row.html.erb`) — Turbo Frame for filter/sort/pagination
- [ ] **1.5** Write tests for ConversionDetailQuery (account scoping, eager loading, not-found)
- [ ] **1.6** Write controller tests for index (pagination, filtering, cross-account isolation)

### Phase 2: Conversion Detail + Journey Visualisation

- [ ] **2.1** Create `Dashboard::ConversionDetailController` with `show` action (or add to existing controller — decide based on route clarity)
- [ ] **2.2** Build conversion detail view — data card, properties table, attribution credits table
- [ ] **2.3** Build journey visualisation partial — load sessions from `journey_session_ids`, compute time gaps, render timeline nodes
- [ ] **2.4** Style journey nodes with channel colours (reuse existing channel colour mapping from dashboard charts)
- [ ] **2.5** Handle responsive layout — horizontal on desktop, vertical stack on mobile
- [ ] **2.6** Handle edge states — empty journey, single touchpoint, many touchpoints
- [ ] **2.7** Write tests for journey rendering (correct ordering, time gap calculation, empty states)

### Phase 3: Identity Detail View

- [ ] **3.1** Add route: `GET /dashboard/identities/:id` (using prefix_id)
- [ ] **3.2** Create `Dashboard::IdentitiesController` with `show` action
- [ ] **3.3** Create `Dashboard::IdentityDetailQuery` — loads identity with visitors, sessions (for channel aggregation), conversions
- [ ] **3.4** Create `Dashboard::EngagementScoreCalculator` — computes RFMB score from identity data
- [ ] **3.5** Build identity detail view — profile header, traits, channel breakdown, conversions table, visitors list, engagement score
- [ ] **3.6** Link identity from conversion detail and conversions table
- [ ] **3.7** Write tests for EngagementScoreCalculator (all tiers, edge cases: no sessions, no revenue, new identity, stale identity)
- [ ] **3.8** Write tests for IdentityDetailQuery (account scoping, cross-account isolation)
- [ ] **3.9** Write controller tests for identity show

### Phase 4: Polish & Navigation

- [ ] **4.1** Add "View conversions" link/tab to existing dashboard navigation
- [ ] **4.2** Link conversions table from unified feed conversion cards
- [ ] **4.3** Breadcrumb navigation: Dashboard → Conversions → Conversion Detail
- [ ] **4.4** Breadcrumb navigation: Dashboard → Identities → Identity Detail
- [ ] **4.5** Visual polish — consistent card styling, empty states, loading states via Turbo
- [ ] **4.6** Mobile responsive testing for journey timeline

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| ConversionDetailQuery returns conversion with journey sessions | `test/services/dashboard/conversion_detail_query_test.rb` | Eager loads sessions from `journey_session_ids` in correct order |
| ConversionDetailQuery scoped to account | Same | Returns nil for other account's conversions |
| ConversionDetailQuery handles empty journey | Same | Returns conversion with empty sessions array |
| IdentityDetailQuery loads full profile | `test/services/dashboard/identity_detail_query_test.rb` | Loads visitors, sessions, conversions |
| IdentityDetailQuery scoped to account | Same | Returns nil for other account's identities |
| EngagementScoreCalculator happy path | `test/services/dashboard/engagement_score_calculator_test.rb` | Returns score 0-100 with correct tier |
| EngagementScoreCalculator — no sessions | Same | Frequency and breadth = 0, still returns valid score |
| EngagementScoreCalculator — no conversions | Same | Monetary = 0, still returns valid score |
| EngagementScoreCalculator — stale identity | Same | Recency decays correctly (90+ days = 0) |
| EngagementScoreCalculator — maxed out | Same | Caps at 100 (20+ sessions, high revenue, 5+ channels, recent) |

### Controller Tests

| Test | File | Verifies |
|------|------|----------|
| GET /dashboard/conversions returns paginated list | `test/controllers/dashboard/conversions_controller_test.rb` | 200, correct count, pagination links |
| GET /dashboard/conversions filters by type | Same | Only matching conversion_type returned |
| GET /dashboard/conversions/:id shows detail | Same | 200, conversion data present |
| GET /dashboard/conversions/:id for wrong account | Same | 404 |
| GET /dashboard/identities/:id shows profile | `test/controllers/dashboard/identities_controller_test.rb` | 200, identity data, engagement score |
| GET /dashboard/identities/:id for wrong account | Same | 404 |

### Manual QA

1. Create several conversions with varying journey lengths (1, 3, 7+ touchpoints)
2. Navigate to conversions table — verify sort, filter, pagination
3. Click a conversion with a multi-session journey — verify timeline renders correctly
4. Verify time gaps between nodes match actual session dates
5. Click identity link — verify identity profile loads
6. Verify engagement score shows appropriate tier
7. Test with anonymous conversion (no identity) — verify graceful handling
8. Test on mobile — verify journey timeline stacks vertically
9. Test with test data toggle — verify test conversions show badge

---

## Definition of Done

- [ ] All tasks completed
- [ ] Tests pass (unit + controller)
- [ ] Conversions table is paginated, filterable, sortable
- [ ] Journey visualisation renders correctly for 1, 3, 7+ touchpoint journeys
- [ ] Identity detail shows profile, channels, conversions, engagement score
- [ ] Cross-account isolation verified (404 for wrong account)
- [ ] Empty states handled gracefully
- [ ] Mobile responsive
- [ ] Manual QA on dev
- [ ] No regressions on existing dashboard
- [ ] Spec updated with final state

---

## Out of Scope

- **Stored engagement scores** — computed on render for now. Materialise into a column/table if performance becomes a concern.
- **Configurable scoring weights** — hardcoded RFMB weights. Make configurable per-account in a future iteration.
- **Journey editing/annotation** — read-only visualisation. No ability to add notes or exclude touchpoints.
- **Identity merge/unmerge UI** — identities are linked via the API's `/identify` call. No manual merge from the dashboard.
- **Funnel analysis** — the `funnel` field exists but funnel-specific views are a separate feature.
- **Export** — CSV/PDF export of conversions or identity profiles. Future enhancement.
- **Real-time updates** — detail views are static on load. No ActionCable streaming to update live.
- **Journey comparison** — comparing two conversions' journeys side-by-side. Future.
- **Predictive scoring** — ML-based lead scoring. The RFMB formula is rule-based and transparent.
