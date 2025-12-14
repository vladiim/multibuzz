# Attribution Dashboard Specification

**Status**: ✅ Complete
**Last Updated**: 2025-12-09
**Epic**: E1S3 - Dashboard

---

## Overview

Build a multi-touch attribution dashboard with two main views:
1. **Conversions View** (Attribution) - Shows attributed conversions and revenue by channel
2. **Events View** (Funnel) - Shows event progression with conversion rates

**Key Features**:
- Skeleton-first loading via Turbo Frames
- Filters: Date range, Attribution model, Channels
- Model comparison: Compare two attribution models side-by-side
- Responsive, clean design following Attio-inspired visual system
- **Bookmarkable URLs**: Filter state persisted in URL params
- **Explicit Apply**: Filters don't auto-apply; user clicks "Apply" to reload

---

## Architecture

### Tech Stack

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Charts | **Highcharts** | Dual Y-axes, stacked bars + line overlay, drilldowns, proven at scale |
| Real-time | **Turbo Frames + Streams** | Skeleton loading, partial updates without full refresh |
| Filters | **Stimulus Controllers** | Declarative JS for filter interactions |
| Styling | **Tailwind CSS** | Existing design system, rapid iteration |

### Loading Strategy: Skeleton First ✅

All sections load via Turbo Frames (including filters, which will have dynamic elements from DB queries like dimensions/metrics).

### URL State Management ✅

Filters persist in URL params for bookmarkability:

```
/dashboard?date_range=30d&model=linear&channels=paid_search,organic_search,email&touch=first_touch
```

### Caching Strategy ✅

**Multi-layer caching for DB query performance (Solid Stack):**

| Layer | Technology | TTL | Scope |
|-------|------------|-----|-------|
| **Query Cache** | Rails.cache (Solid Cache) | 5-15 min | Per account + filter combo |

**Cache Key Pattern**:
```ruby
cache_key = [
  "dashboard/conversions",
  current_account.id,
  params[:date_range],
  params[:model],
  params[:channels].sort.join(",")
].join("/")
```

---

## Implementation Phases

### Phase 1: Prototype with Dummy Data ✅

- [x] Dashboard shell with Turbo Frames (filters, conversions, events)
- [x] Skeleton loading states for all sections
- [x] Filter bar with dropdown multi-select for channels
- [x] **Apply button** pattern (no auto-apply)
- [x] **URL param persistence** (bookmarkable filters)
- [x] Conversions section (cards + bar chart)
- [x] Funnel tab (renamed from Journeys) with stacked column + conversion rate line
- [x] Basic comparison mode (side-by-side)
- [x] Stimulus controllers (filter, dropdown, chart, comparison)
- [x] Highcharts integration

### Phase 2: Wire Up Real Data ✅

- [x] Dashboard::ConversionsDataService (queries attribution_credits)
- [x] Dashboard::FunnelDataService (queries events + sessions)
- [x] Dashboard::DateRangeParser (value object for date parsing)
- [x] Dashboard::Scopes::CreditsScope (filtered AR relation builder)
- [x] Dashboard::Scopes::EventsScope (filtered AR relation builder)
- [x] Dashboard::Queries::TotalsQuery (sum credits/revenue)
- [x] Dashboard::Queries::ByChannelQuery (group by channel)
- [x] Dashboard::Queries::TimeSeriesQuery (daily breakdown)
- [x] Dashboard::Queries::TopCampaignsQuery (top campaigns per channel)
- [x] Dashboard::Queries::FunnelStagesQuery (funnel stage data)
- [x] Dashboard::Queries::ByConversionNameQuery (breakdown by dimension)
- [x] Dashboard::Queries::JourneyMetricsQuery (avg days, channels, visits)
- [x] Turbo Frame endpoints return real data
- [x] Date range filtering with URL params (7d, 30d, 90d, custom)
- [x] **Filter verification** (44+ tests covering date, channel, model filters)

### Phase 3: Caching & Performance ✅

- [x] **Rails.cache** for query results (memory_store dev, Solid Cache prod, 5 min TTL)
- [x] **Cache key** based on account prefix_id + MD5 hash of filter params
- [x] **Cache invalidation** on attribution credit create/update/destroy
- [x] **Dashboard::CacheInvalidator** service for explicit invalidation

### Phase 4: Polish & Accessibility (Deferred)

These items are deferred for future enhancement:

- [ ] Loading states and error handling
- [ ] Responsive design (mobile/tablet)
- [ ] Accessibility (ARIA labels, keyboard nav)
- [ ] Export functionality (CSV/PNG)
- [ ] Fragment caching for chart HTML
- [ ] Continuous aggregates hourly refresh
- [ ] Manual refresh button for users

---

## File Structure ✅

```
app/
├── controllers/
│   └── dashboard/
│       ├── base_controller.rb        # Shared filter parsing
│       ├── main_controller.rb        # Main dashboard page
│       ├── filters_controller.rb     # Turbo frame endpoint for filters
│       ├── conversions_controller.rb # Turbo frame endpoint for conversions
│       ├── events_controller.rb      # Turbo frame endpoint for funnel
│       ├── conversion_filters_controller.rb # AJAX endpoints for filters
│       └── view_mode_controller.rb   # Test/production mode toggle
├── services/
│   └── dashboard/
│       ├── conversions_data_service.rb # Main data orchestrator (cached)
│       ├── funnel_data_service.rb      # Funnel queries
│       ├── cache_invalidator.rb        # Cache management
│       ├── conversion_dimensions_service.rb # Available dimensions
│       ├── conversion_values_service.rb    # Values for autocomplete
│       ├── queries/
│       │   ├── totals_query.rb
│       │   ├── by_channel_query.rb
│       │   ├── by_conversion_name_query.rb
│       │   ├── time_series_query.rb
│       │   ├── top_campaigns_query.rb
│       │   ├── funnel_stages_query.rb
│       │   └── journey_metrics_query.rb
│       └── scopes/
│           ├── credits_scope.rb
│           ├── events_scope.rb
│           ├── filtered_credits_scope.rb
│           └── operators/
│               ├── base.rb
│               ├── equals.rb
│               ├── not_equals.rb
│               ├── contains.rb
│               ├── greater_than.rb
│               └── less_than.rb
├── views/
│   └── dashboard/
│       ├── main/
│       │   └── show.html.erb
│       ├── filters/
│       │   ├── show.html.erb
│       │   └── _skeleton.html.erb
│       ├── conversions/
│       │   ├── show.html.erb
│       │   ├── _skeleton.html.erb
│       │   ├── _full_dashboard.html.erb
│       │   ├── _comparison_dashboard.html.erb
│       │   ├── _by_conversion_name_chart.html.erb
│       │   └── _conversion_filters.html.erb
│       └── events/
│           ├── show.html.erb
│           └── _skeleton.html.erb
└── javascript/
    └── controllers/
        ├── dashboard_controller.js
        ├── chart_controller.js
        ├── filter_controller.js
        ├── dropdown_controller.js
        ├── conversion_filter_controller.js
        └── comparison_controller.js
```

---

## Test Coverage Summary ✅

- **Controller tests**: 811+ lines across dashboard controllers
- **Service tests**: 2519+ lines across dashboard services
- **Query tests**: TotalsQuery, ByChannelQuery, ByConversionNameQuery, TimeSeriesQuery, JourneyMetricsQuery
- **Scope tests**: CreditsScope, EventsScope, FilteredCreditsScope
- **Helper tests**: DashboardHelper (hidden_filter_params)

---

## Key Features Implemented ✅

### Single Model View
- 6 KPI cards (Conversions, Revenue, AOV, Avg Days, Avg Channels, Avg Visits)
- Selectable metric for main chart
- Channel attribution bar chart
- Conversions by Name chart with breakdown dimension selector

### Comparison Mode
- Side-by-side comparison of two attribution models
- Panel index for color theming
- Synchronized filters across panels

### Conversion Filters
- PostHog-style filter bar
- Dynamic property discovery
- Multiple operators (equals, not_equals, contains, greater_than, less_than)
- Filter preservation across breakdown dimension changes

### Funnel View
- Dynamic funnel stages from customer event data
- Stacked bar chart by channel
- Conversion rate line overlay
- Touch filter modes (first touch, last touch, assisted)

---

## Resolved Decisions

| Decision | Resolution |
|----------|------------|
| Caching strategy | Solid Cache with account + filter params in cache key |
| Filter apply behavior | Explicit "Apply" button, no auto-apply |
| URL state | Filters persist in URL params for bookmarkability |
| Channel filter UI | Dropdown with multi-select checkboxes |
| Filters loading | Via Turbo Frame (dynamic options from DB) |
| Property storage | Flat structure at root level (not nested) |
