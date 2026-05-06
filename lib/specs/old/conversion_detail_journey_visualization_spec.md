# Conversion Detail & Journey Visualization Specification

**Date:** 2026-03-05
**Priority:** P1
**Status:** Complete
**Branch:** `feature/session-bot-detection`

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

## Solution

Three interconnected views, all server-rendered with Turbo navigation:

### 1. Conversions Table (Browse)

A paginated table of individual conversions, accessible via the "Browse" button on the dashboard. Each row shows key data at a glance. Located at `GET /dashboard/conversion_list`.

**Columns:**

| Column | Source |
|--------|--------|
| Date | `conversion.converted_at` |
| Type | `conversion.conversion_type` (badge) + `is_test` / `is_acquisition` badges |
| Revenue | `conversion.revenue` + `conversion.currency` |
| Sessions | `journey_session_ids.size` shown as "X sessions" |
| Touchpoints | `journey_session_ids.length` |
| Identity | `conversion.identity.external_id` (link to identity detail) or "Anonymous" |

**Interactions:**
- Click row → opens Conversion Detail view via `Turbo.visit`
- Click identity link → opens Identity Detail view (with `event.stopPropagation()`)
- Filter by `conversion_type` param
- Default sort: `converted_at` desc
- Paginate (25 per page via `Pagination` concern)

### 2. Conversion Detail + Journey Visualisation

A dedicated page at `GET /dashboard/conversion_list/:prefix_id` showing the full conversion record and a visual journey timeline.

**Conversion data section** (card with key-value pairs):

| Field | Source |
|-------|--------|
| Conversion ID | `conversion.prefix_id` (`conv_...`) |
| Type | `conversion.conversion_type` |
| Revenue | `conversion.revenue` formatted with `conversion.currency` |
| Date | `conversion.converted_at` formatted |
| Time to convert | Computed: first journey session → `converted_at` (days) |
| Funnel | `conversion.funnel` (if present) |
| Acquisition | `conversion.is_acquisition` badge |
| Identity | Link to identity detail (or "Anonymous") |
| Visitor | `conversion.visitor.prefix_id` |
| Properties | `conversion.properties` rendered as key-value table (inline, not extracted to partial) |

**Attribution credits section** (table):

| Model | Channel | Credit | Revenue | Source | Campaign |
|-------|---------|--------|---------|--------|----------|

**Journey visualisation** (the differentiator):

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│  Paid Search │──3 d───▶│ Paid Social  │──2 d───▶│Organic Search│──0 d───▶│ ✓ Converted  │
│  Google Ads  │         │  Instagram   │         │   google     │         │  Purchase    │
│  Mar 1, 2026 │         │  Mar 4, 2026 │         │  Mar 6, 2026 │         │  Mar 6, 2026 │
│  example.com │         │  example.com │         │  example.com │         │  $249.00     │
└─────────────┘         └─────────────┘         └─────────────┘         └─────────────┘
```

Each journey node shows:
- Channel name (with channel-coloured left border)
- Source (from session `initial_utm.source` or referrer host)
- Date (`session.started_at`)
- Landing page host (`session.landing_page_host`)
- Time gap to next node (edge label, formatted via `format_time_gap`)

The final node is the conversion itself (green border, shows type + revenue).

**Implementation:** Server-rendered HTML with Tailwind. Horizontal flow on desktop (`hidden sm:flex`), vertical stack on mobile (`sm:hidden`). Connected by arrows with time-gap labels. Each session node is a `<div>` with channel-coloured left border. No JS charting library needed.

### 3. Identity Detail View

A dedicated page at `GET /dashboard/identities/:prefix_id` showing a full identity profile.

**Profile header:**
- Avatar initials (first 2 chars of `external_id`)
- External ID (`identity.external_id`)
- First/last identified dates (relative via `time_ago_in_words`)
- Engagement score badge with tier styling

**Engagement score breakdown:**
- Component bars (recency, frequency, monetary, breadth) with percentage fill

**Traits section:**
- Key-value rendering of `identity.traits` JSONB
- "No traits collected" empty state

**Channels section:**
- Aggregated channel breakdown across all sessions from all linked visitors
- Percentage bars showing channel distribution with session counts

**Conversions section:**
- Compact table: Date, Type (badge), Revenue
- Click through to conversion detail via `Turbo.visit`
- Total revenue shown in header

**Visitors section:**
- List of linked visitors with `prefix_id` and `last_seen_at` (relative)
- "No visitors linked" empty state

**Engagement Score:**

A computed score (not stored) providing a quick read on identity quality. Calculated on render from existing data:

| Signal | Weight | Calculation | Constant |
|--------|--------|-------------|----------|
| Recency | 25% | Days since `last_identified_at` → linear decay (1.0 if today, 0.0 if 90+ days) | `RECENCY_DECAY_DAYS = 90` |
| Frequency | 25% | Total session count across all visitors → normalised (cap at 20 sessions = 1.0) | `FREQUENCY_SESSION_CAP = 20` |
| Monetary | 25% | Total conversion revenue → normalised (cap at account's p95 revenue = 1.0, floor $1) | `REVENUE_PERCENTILE = 0.95`, `REVENUE_FLOOR = 1.0` |
| Breadth | 25% | Distinct channels across all sessions → normalised (cap at 5 channels = 1.0) | `CHANNEL_DIVERSITY_CAP = 5` |

Score = `(components.values.sum / COMPONENT_COUNT × SCORE_SCALE).round`, displayed as 0-100 with tier labels:
- 80-100: `TIER_HOT` "Hot" (red badge)
- 60-79: `TIER_WARM` "Warm" (orange badge)
- 40-59: `TIER_ENGAGED` "Engaged" (yellow badge)
- 20-39: `TIER_COOL` "Cool" (blue badge)
- 0-19: `TIER_COLD` "Cold" (grey badge)

All thresholds, caps, and labels are named constants in `EngagementScoreCalculator`. Component values capped at `MAX_COMPONENT = 1.0` via a `cap()` helper.

This is intentionally simple and computed on the fly. No new DB columns. Can evolve later into a stored/configurable scoring model.

---

### Data Flow

```
Dashboard "Browse" button
    → GET /dashboard/conversion_list
    → ConversionDetailController#index — paginated, filterable
    → click row → GET /dashboard/conversion_list/:prefix_id
    → ConversionDetailController#show
    → ConversionDetailQuery loads conversion + journey sessions + credits
    → Journey sessions loaded via journey_session_ids array, ordered to match
    → Time gaps computed between consecutive sessions
    → Rendered as timeline nodes with time-gap labels
    → Click identity link → GET /dashboard/identities/:prefix_id
    → IdentitiesController#show
    → IdentityDetailQuery loads identity + visitors + conversions + channel breakdown
    → EngagementScoreCalculator computes RFMB score on render
```

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Conversion detail as page vs panel | **Page** | Journey visualisation needs horizontal space; properties table can be large; URL-addressable for sharing |
| Journey rendering | **Server-rendered HTML** | Tailwind can handle the visual; no chart library overhead; works with Turbo navigation; accessible |
| Engagement score storage | **Computed on render** | Avoids schema changes, background jobs, staleness. Identity detail is low-traffic (inspecting individual records). Can materialise later if needed |
| Conversions table location | **New route under dashboard** | Keeps existing aggregated dashboard intact; conversions table is a different mental model (individual records vs aggregated metrics) |
| Controller naming | **ConversionDetailController** | Avoids collision with existing `ConversionsController` (aggregated KPIs); clear separation of concerns |
| Identity detail as page vs modal | **Page** | Rich content (traits, conversions table, channel chart, visitors list) — too much for a modal |
| Engagement score formula | **Equal-weight RFMB** | Simple, transparent, no ML. Recency/Frequency/Monetary is proven (RFM). Added Breadth for multi-channel signal. Weights can be tuned later |
| Journey data attachment | **Singleton methods on AR record** | Avoids model changes; `ConversionDetailQuery` attaches `journey_sessions`, `journey_time_gaps`, `days_to_convert` as computed fields |
| Partials vs inline | **Inline for small sections** | Properties, engagement score breakdown, and channel chart are rendered inline in their parent views rather than extracted to partials — simpler with no reuse need |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| **Happy path** | Conversion with journey + identity | Full detail, journey vis, identity link |
| **No journey** | `journey_session_ids` empty | Show conversion data + credits, journey section shows "No journey data" |
| **Single touchpoint** | `journey_session_ids.length == 1` | Show single node → conversion (no time gap) |
| **Anonymous** | `identity_id` nil | Identity field shows "Anonymous" — no link |
| **No revenue** | `revenue` nil | Revenue shows "—", engagement score monetary component = 0 |
| **No properties** | `properties` empty hash | Properties section hidden |
| **No traits** | `identity.traits` empty hash | Traits section shows "No traits collected" |
| **Cross-device** | Identity has multiple visitors | Visitors section shows all linked visitors; journey may span devices |
| **Many touchpoints** | 20+ sessions in journey | Horizontal scroll on desktop, vertical stack on mobile |
| **Conversion not found** | Invalid prefix_id | `head :not_found` (404) |
| **Wrong account** | Conversion belongs to different account | `head :not_found` (multi-tenancy: never leak existence) |
| **Test data** | `is_test: true` | Shown with "TEST" badge |
| **Acquisition** | `is_acquisition: true` | Shown with "ACQ" badge |
| **Identity with no conversions** | Identity exists but zero conversions | Conversions section shows "No conversions yet"; engagement monetary score = 0 |
| **Identity with no channel data** | No sessions for linked visitors | Channel section shows "No channel data" |

---

## Key Files

| File | Purpose |
|------|---------|
| `config/routes.rb` | `get "conversion_list"` → `conversion_detail#index`, `get "conversion_list/:id"` → `conversion_detail#show`, `get "identities/:id"` → `identities#show` |
| `app/controllers/dashboard/conversion_detail_controller.rb` | `index` (paginated, filterable) and `show` (detail via query object) |
| `app/controllers/dashboard/identities_controller.rb` | `show` action — loads identity + computes engagement score |
| `app/services/dashboard/conversion_detail_query.rb` | Query object — loads conversion with eager-loaded journey sessions (ordered), time gaps, days-to-convert, credits, identity, visitor |
| `app/services/dashboard/identity_detail_query.rb` | Query object — loads identity with visitors, conversions, computes channel breakdown and total revenue |
| `app/services/dashboard/engagement_score_calculator.rb` | RFMB score calculator — all constants, functional `#call` with `.then` pipeline |
| `app/helpers/dashboard_helper.rb` | `format_time_gap(days)` — renders gap as "< 1 h", "X hr", "X day", "X mo" |
| `app/views/dashboard/conversion_detail/index.html.erb` | Conversions table with pagination |
| `app/views/dashboard/conversion_detail/_conversion_row.html.erb` | Single row — clickable via `Turbo.visit` |
| `app/views/dashboard/conversion_detail/show.html.erb` | Conversion detail page — data card, properties (inline), journey partial, attribution credits partial |
| `app/views/dashboard/conversion_detail/_journey.html.erb` | Journey timeline — desktop horizontal + mobile vertical, channel-coloured nodes |
| `app/views/dashboard/conversion_detail/_attribution_credits.html.erb` | Attribution credits table |
| `app/views/dashboard/identities/show.html.erb` | Identity profile — header, score breakdown (inline), traits, visitors, channels (inline), conversions table |
| `app/views/dashboard/show.html.erb` | Modified — added "Browse" button linking to conversion list |
| `app/views/dashboard/live_events/_conversion_card.html.erb` | Modified — added "View journey" link to conversion detail |

---

## Implementation Tasks

### Phase 1: Conversions Table + Query

- [x] **1.1** Add routes: `GET /dashboard/conversion_list` (index) and `GET /dashboard/conversion_list/:id` (show)
- [x] **1.2** Create `Dashboard::ConversionDetailQuery` — loads conversion scoped to account with journey sessions (ordered), attribution credits, identity, visitor
- [x] **1.3** Create `Dashboard::ConversionDetailController` with `index` and `show` actions — paginated, filterable by `conversion_type`
- [x] **1.4** Build conversions table view (`index.html.erb` + `_conversion_row.html.erb`)
- [x] **1.5** Write tests for ConversionDetailQuery (account scoping, eager loading, journey ordering, time gaps, days-to-convert, not-found)
- [x] **1.6** Write controller tests for index (pagination, filtering, cross-account isolation, auth)

### Phase 2: Conversion Detail + Journey Visualisation

- [x] **2.1** Build conversion detail view — data card, properties (inline), attribution credits table
- [x] **2.2** Build journey visualisation partial — load sessions from `journey_session_ids`, compute time gaps, render timeline nodes
- [x] **2.3** Style journey nodes with channel colours (channel colour mapping in `_journey.html.erb`)
- [x] **2.4** Handle responsive layout — horizontal on desktop (`hidden sm:flex`), vertical stack on mobile (`sm:hidden`)
- [x] **2.5** Handle edge states — empty journey, single touchpoint
- [x] **2.6** Write controller tests for show (loading, journey sessions, not-found, auth)

### Phase 3: Identity Detail View

- [x] **3.1** Add route: `GET /dashboard/identities/:id` (using prefix_id)
- [x] **3.2** Create `Dashboard::IdentitiesController` with `show` action
- [x] **3.3** Create `Dashboard::IdentityDetailQuery` — loads identity with visitors, conversions, computes channel breakdown + total revenue
- [x] **3.4** Create `Dashboard::EngagementScoreCalculator` — computes RFMB score with all named constants and `.then` pipeline
- [x] **3.5** Build identity detail view — profile header, score breakdown, traits, channel bars, conversions table, visitors list
- [x] **3.6** Link identity from conversion detail and conversions table
- [x] **3.7** Write tests for EngagementScoreCalculator (all tiers, recency decay, frequency cap, breadth cap, monetary zero, cross-device)
- [x] **3.8** Write tests for IdentityDetailQuery (account scoping, eager loading, channel breakdown, total revenue, cross-account isolation)
- [x] **3.9** Write controller tests for identity show (loading, engagement score, not-found, auth)

### Phase 4: Polish & Navigation

- [x] **4.1** Add "Browse" button to dashboard toolbar (next to Filters/Export)
- [x] **4.2** Add "View journey" link to unified feed conversion cards
- [x] **4.3** Breadcrumb navigation: Dashboard → Conversions → Conversion Detail
- [x] **4.4** Breadcrumb navigation: Dashboard → Conversions → Identity Detail
- [x] **4.5** Visual polish — consistent card styling, empty states, badge styling

---

## Testing Strategy

### Unit Tests (30 tests)

| Test | File | Verifies |
|------|------|----------|
| Returns conversion with basic attributes | `test/services/dashboard/conversion_detail_query_test.rb` | Loads conversion, correct type |
| Returns conversion revenue | Same | Revenue as float |
| Eager loads visitor | Same | No N+1 queries |
| Eager loads identity | Same | No N+1 queries when linked |
| Returns nil identity when not linked | Same | Graceful nil handling |
| Eager loads attribution credits | Same | No N+1 queries |
| Loads journey sessions in order | Same | Preserves `journey_session_ids` array order |
| Returns empty journey sessions | Same | Empty array when no journey |
| Returns nil for other account | Same | Multi-tenancy isolation |
| Returns nil for nonexistent prefix_id | Same | Not-found handling |
| Computes time gaps | Same | Correct day gaps between sessions |
| Computes total time to convert | Same | First session → conversion |
| Returns identity with basic attributes | `test/services/dashboard/identity_detail_query_test.rb` | Loads identity, correct external_id |
| Eager loads visitors | Same | No N+1 queries |
| Eager loads conversions | Same | No N+1 queries |
| Returns nil for other account | Same | Multi-tenancy isolation |
| Returns nil for nonexistent prefix_id | Same | Not-found handling |
| Computes channel breakdown | Same | Hash with correct channels |
| Computes total revenue | Same | Sum across conversions |
| Channel breakdown scoped to linked visitors | Same | Excludes unlinked visitors |
| Returns score 0-100 | `test/services/dashboard/engagement_score_calculator_test.rb` | Valid range |
| Returns tier label | Same | One of Hot/Warm/Engaged/Cool/Cold |
| Returns component breakdown | Same | All 4 components present |
| Hot tier for highly engaged | Same | Score >= 80, tier = Hot |
| Cold tier for stale identity | Same | Score <= 19, tier = Cold |
| Recency decays over 90 days | Same | Monotonic decay, zero at 90+ |
| Frequency capped at 20 | Same | Component = 1.0 at cap |
| Monetary zero with no conversions | Same | Component = 0.0 |
| Breadth increases with channels | Same | More channels = higher score |
| Breadth capped at 5 | Same | Component = 1.0 at cap |
| Cross-device frequency | Same | Counts sessions across all linked visitors |

### Controller Tests (16 tests)

| Test | File | Verifies |
|------|------|----------|
| Index renders conversions table | `test/controllers/dashboard/conversion_detail_controller_test.rb` | 200 |
| Index scoped to account | Same | Only current account's conversions |
| Index paginates | Same | Max 25 per page |
| Index filters by type | Same | Only matching conversion_type |
| Index sorts desc by default | Same | Most recent first |
| Index requires login | Same | Redirects to login |
| Show renders detail | Same | 200 |
| Show loads journey sessions | Same | Correct count |
| Show 404 for other account | Same | Multi-tenancy |
| Show 404 for nonexistent | Same | Not-found |
| Show requires login | Same | Redirects to login |
| Identity show renders | `test/controllers/dashboard/identities_controller_test.rb` | 200 |
| Identity show loads identity | Same | @identity set |
| Identity show computes score | Same | Score has :score and :tier |
| Identity 404 for other account | Same | Multi-tenancy |
| Identity 404 for nonexistent | Same | Not-found |
| Identity requires login | Same | Redirects to login |

### Manual QA

1. Create several conversions with varying journey lengths (1, 3, 7+ touchpoints)
2. Navigate to conversions table via Browse button — verify filter, pagination
3. Click a conversion with a multi-session journey — verify timeline renders correctly
4. Verify time gaps between nodes match actual session dates
5. Click identity link — verify identity profile loads
6. Verify engagement score shows appropriate tier
7. Test with anonymous conversion (no identity) — verify graceful handling
8. Test on mobile — verify journey timeline stacks vertically
9. Test with test data — verify TEST badge shown

---

## Definition of Done

- [x] All tasks completed
- [x] Tests pass (46 new tests — unit + controller)
- [x] Conversions table is paginated, filterable by type
- [x] Journey visualisation renders correctly for 1, 3, 7+ touchpoint journeys
- [x] Identity detail shows profile, channels, conversions, engagement score
- [x] Cross-account isolation verified (404 for wrong account)
- [x] Empty states handled gracefully
- [x] Mobile responsive (vertical journey stack)
- [x] Manual QA on dev (30 UAT customers generated)
- [x] No regressions on existing dashboard
- [x] Spec updated with final state

---

## Future Enhancements

- **Channels + time-to-convert columns in conversions table** — requires loading sessions per row (N+1 concern); consider materialising these fields on conversion
- **Sorting** — add sort controls (by revenue, date, time-to-convert) to conversions table
- **Date range + channel filters** — extend conversions table filtering beyond `conversion_type`
- **Visitor first_seen_at** — show in identity visitors list alongside last_seen_at
- **Landing page path** — show full path (host + path) in journey nodes, not just host

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
