# Attribution Dashboard Specification

**Status**: Draft - Pending Approval
**Last Updated**: 2025-11-28
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

### Loading Strategy: Skeleton First

All sections load via Turbo Frames (including filters, which will have dynamic elements from DB queries like dimensions/metrics).

```
┌─────────────────────────────────────────────────────────┐
│ Dashboard (immediate render - shell only)               │
├─────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────┐ │
│ │ turbo-frame id="filters-section"                    │ │
│ │ [░░░░░░░░░░] [░░░░░░░░░░] [░░░░░░░░░░] [Apply]     │ │ <- Skeleton filters
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ turbo-frame id="conversions-section"                │ │
│ │ ┌───────┐ ┌───────┐  <- Skeleton cards             │ │
│ │ │░░░░░░░│ │░░░░░░░│                                │ │
│ │ └───────┘ └───────┘                                │ │
│ │ ┌─────────────────────────────────────────────────┐│ │
│ │ │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░││ │
│ │ │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░││ │ <- Skeleton chart
│ │ │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░││ │
│ │ └─────────────────────────────────────────────────┘│ │
│ └─────────────────────────────────────────────────────┘ │
│                                                         │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ turbo-frame id="events-section"                     │ │
│ │ (Skeleton funnel chart)                            │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**Flow**:
1. Initial page render with skeleton placeholders (shell only)
2. Turbo Frames lazy-load each section independently (filters, conversions, events)
3. Charts render when data arrives
4. User adjusts filters → clicks **"Apply"** → URL params updated → page reloads with new state

### URL State Management

Filters persist in URL params for bookmarkability:

```
/dashboard?date_range=30d&model=linear&channels=paid_search,organic_search,email&touch=first_touch
```

**Benefits**:
- Bookmarkable/shareable dashboard states
- Browser back/forward navigation works
- Deep links to specific views

### Data Flow (Apply Button Pattern)

```
User adjusts filters (no network request yet)
     │
     ▼
User clicks "Apply" button
     │
     ▼
Stimulus Controller builds URL with query params
     │
     ▼
Turbo.visit(newUrl) - full page navigation with new params
     │
     ▼
Rails Controller parses params from URL
     │
     ▼
Query Services (with caching) fetch data
     │
     ▼
Turbo Frames render with real data
     │
     ▼
Highcharts render in Stimulus controllers
```

### Caching Strategy

**Multi-layer caching for DB query performance (Solid Stack):**

| Layer | Technology | TTL | Scope |
|-------|------------|-----|-------|
| **Query Cache** | Rails.cache (Solid Cache) | 5-15 min | Per account + filter combo |
| **Continuous Aggregates** | TimescaleDB | Hourly refresh | Pre-computed daily/weekly rollups |
| **Fragment Cache** | Rails fragment caching | Until data changes | Chart HTML partials |

**Cache Key Pattern**:
```ruby
# Example cache key for conversions data
cache_key = [
  "dashboard/conversions",
  current_account.id,
  params[:date_range],
  params[:model],
  params[:channels].sort.join(",")
].join("/")

# e.g., "dashboard/conversions/acct_123/30d/linear/email,organic_search,paid_search"
```

**Invalidation Strategy**:
- Event ingestion triggers cache busting for affected account
- Continuous aggregates auto-refresh hourly
- Manual refresh button for users who need immediate data

---

## Layout Design

### Main Dashboard Structure

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Header: Dashboard                                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ FILTERS BAR (turbo-frame id="filters-section")                       ││
│ │ ┌───────────┐ ┌──────────────────┐ ┌──────────────┐ ┌──────────────┐││
│ │ │Date Range │ │ Attribution Model│ │ Channels   ▼ │ │   [Apply]    │││
│ │ │ Last 30d ▼│ │ Linear         ▼ │ │ (dropdown)   │ │              │││
│ │ └───────────┘ └──────────────────┘ └──────────────┘ └──────────────┘││
│ │                                    ┌──────────────┐                  ││
│ │                                    │ ☑ Select All │ <- Dropdown     ││
│ │                                    │ ☑ Paid Search│    opens with   ││
│ │                                    │ ☑ Organic    │    checkboxes   ││
│ │                                    │ ☑ Email      │                  ││
│ │                                    │ ☐ Social     │                  ││
│ │                                    │ ☑ Direct     │                  ││
│ │                                    └──────────────┘                  ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ CONVERSIONS (Attribution)                                            ││
│ │                                                                      ││
│ │ ┌─────────────────────┐  ┌─────────────────────┐                    ││
│ │ │ Total Conversions   │  │ Total Revenue       │                    ││
│ │ │ 2,382               │  │ $147,230            │                    ││
│ │ │ +12.4% vs prior     │  │ +8.7% vs prior      │                    ││
│ │ └─────────────────────┘  └─────────────────────┘                    ││
│ │                                                                      ││
│ │ ┌────────────────────────────────────────────────────────────────┐  ││
│ │ │                                                                │  ││
│ │ │  Channel Attribution (Stacked Bar Chart)                       │  ││
│ │ │  Y-axis: Credits / Revenue                                     │  ││
│ │ │  X-axis: Channels                                              │  ││
│ │ │                                                                │  ││
│ │ └────────────────────────────────────────────────────────────────┘  ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ EVENTS (Conversion Funnel)                                           ││
│ │                                                                      ││
│ │ Touch Filter: [First Touch] [Last Touch] [Assisted]                 ││
│ │                                                                      ││
│ │ ┌────────────────────────────────────────────────────────────────┐  ││
│ │ │                                                                │  ││
│ │ │  Stacked Bar + Line (Conversion Rate) Chart                    │  ││
│ │ │  Y-left: Count (log scale)                                     │  ││
│ │ │  Y-right: Conversion Rate % (log scale)                        │  ││
│ │ │  X-axis: Funnel Stages                                         │  ││
│ │ │                                                                │  ││
│ │ └────────────────────────────────────────────────────────────────┘  ││
│ └──────────────────────────────────────────────────────────────────────┘│
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Model Comparison Feature

### Recommendation: Side-by-Side with Diff Overlay

Based on research from [Adobe Analytics Attribution IQ](https://www.adobe.com/content/dam/dx/us/en/products/analytics/marketing-attribution/pdfs/54658.en.analytics.tipsheet.tips-tricks_attribution-IQ.pdf), [Google Analytics Model Comparison Tool](https://support.google.com/analytics/answer/6148697?hl=en), and [Databox Marketing Attribution Dashboard](https://databox.com/marketing-attribution-dashboard), the recommended approach combines:

1. **Toggle Button Group** to select comparison mode
2. **Side-by-Side Charts** when comparing two models
3. **Delta Indicators** showing % difference

### Comparison Mode UI

```
┌─────────────────────────────────────────────────────────────────────────┐
│ COMPARISON MODE                                                          │
│                                                                          │
│ ┌────────────────────────────────────────────────────────────────────┐  │
│ │ Compare: [Linear ▼] vs [First Touch ▼]    [Exit Comparison ✕]     │  │
│ └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│ ┌────────────────────────────┐  ┌────────────────────────────────────┐  │
│ │ LINEAR MODEL               │  │ FIRST TOUCH MODEL                  │  │
│ │                            │  │                                    │  │
│ │ Total: 2,382               │  │ Total: 2,382                       │  │
│ │                            │  │                                    │  │
│ │ ┌────────────────────────┐ │  │ ┌────────────────────────────────┐ │  │
│ │ │                        │ │  │ │                                │ │  │
│ │ │   Channel Chart A      │ │  │ │   Channel Chart B              │ │  │
│ │ │                        │ │  │ │                                │ │  │
│ │ └────────────────────────┘ │  │ └────────────────────────────────┘ │  │
│ └────────────────────────────┘  └────────────────────────────────────┘  │
│                                                                          │
│ ┌────────────────────────────────────────────────────────────────────┐  │
│ │ DELTA TABLE                                                        │  │
│ │ Channel       │ Linear │ First Touch │ Δ Credits │ Δ Revenue      │  │
│ │ ────────────────────────────────────────────────────────────────── │  │
│ │ Paid Search   │ 450    │ 650         │ -200 ▼   │ -$12,000       │  │
│ │ Organic       │ 380    │ 520         │ -140 ▼   │ -$8,400        │  │
│ │ Email         │ 320    │ 80          │ +240 ▲   │ +$14,400       │  │
│ │ Social        │ 280    │ 200         │ +80 ▲    │ +$4,800        │  │
│ └────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

### Interaction Flow

1. User clicks "Compare Models" button (hidden by default)
2. Second model selector appears
3. Dashboard layout splits into two columns
4. Charts render side-by-side with synced axes
5. Delta table appears below showing differences
6. "Exit Comparison" button returns to single model view

---

## Events Funnel Chart

### Reference Design (from your screenshot)

The funnel chart shows:
- **X-axis**: Funnel stages (Visits, Event 1, Event 2, etc.)
- **Y-left**: Count (logarithmic scale)
- **Y-right**: Conversion Rate % (logarithmic scale)
- **Bars**: Stacked by channel (color-coded)
- **Line**: Conversion rate overlay with data labels

### Touch Filter Modes

Based on the architecture from `lib/docs/architecture/conversion_funnel_analysis.md`:

| Filter | Description |
|--------|-------------|
| **First Touch** | Users who first visited via this channel |
| **Last Touch** | Users who converted via this channel |
| **Assisted** | Users who had this channel anywhere in journey (not first/last) |

```ruby
# Service interface
Funnel::ChannelSegmentationService
  .new(account, date_range)
  .segment_by_channel(channel, mode: :first_touch) # or :last_touch, :assisted
```

### Chart Configuration (Highcharts)

```javascript
const funnelChartOptions = {
  chart: { type: 'column' },
  title: { text: 'Conversion Funnel by Channel' },

  xAxis: {
    categories: funnelStages, // ['Visits', 'Add to Cart', 'Checkout', 'Purchase']
    labels: { rotation: -45, style: { fontSize: '11px' } }
  },

  yAxis: [{
    // LEFT: Count (logarithmic)
    type: 'logarithmic',
    title: { text: 'Count (log scale)' },
    min: 100,
    max: 1000000
  }, {
    // RIGHT: Conversion Rate (logarithmic)
    type: 'logarithmic',
    title: { text: 'Conversion Rate (%, log scale)', style: { color: '#ef4444' } },
    opposite: true,
    min: 0.1,
    max: 10000,
    labels: { format: '{value}%' }
  }],

  plotOptions: {
    column: { stacking: 'normal' }
  },

  series: [
    // Channel series (bars)
    ...channels.filter(c => selectedChannels.includes(c.key)).map(channel => ({
      name: channel.label,
      type: 'column',
      color: channel.color,
      data: funnelData.map(d => d[channel.key]),
      yAxis: 0
    })),
    // Conversion rate line
    {
      name: 'Conversion Rate',
      type: 'line',
      color: '#ef4444',
      data: funnelData.map(d => d.conversionRate),
      yAxis: 1,
      marker: { enabled: true, radius: 6 },
      dataLabels: { enabled: true, format: '{y}%', style: { fontWeight: 'bold' } }
    }
  ]
};
```

---

## Data Structures

### Channel Configuration

```javascript
const CHANNELS = [
  { key: 'paid_search', label: 'Paid Search', color: '#FF6B6B' },
  { key: 'organic_search', label: 'Organic Search', color: '#4ECDC4' },
  { key: 'paid_social', label: 'Paid Social', color: '#45B7D1' },
  { key: 'organic_social', label: 'Organic Social', color: '#96CEB4' },
  { key: 'email', label: 'Email', color: '#FFEAA7' },
  { key: 'display', label: 'Display', color: '#DDA0DD' },
  { key: 'referral', label: 'Referral', color: '#98D8C8' },
  { key: 'direct', label: 'Direct', color: '#B8B8D1' },
  { key: 'affiliate', label: 'Affiliate', color: '#F7DC6F' },
  { key: 'video', label: 'Video', color: '#BB8FCE' },
  { key: 'other', label: 'Other', color: '#85929E' }
];
```

### Dummy Data Structure (Prototype Phase)

```javascript
// Conversions by Channel (Attribution)
const conversionsByChannel = {
  dateRange: { start: '2025-11-01', end: '2025-11-28' },
  model: 'linear',
  totals: {
    conversions: 2382,
    revenue: 147230,
    priorPeriodChange: { conversions: 12.4, revenue: 8.7 }
  },
  byChannel: [
    { channel: 'paid_search', credits: 450, revenue: 27000, percentage: 18.9 },
    { channel: 'organic_search', credits: 380, revenue: 22800, percentage: 16.0 },
    { channel: 'email', credits: 320, revenue: 19200, percentage: 13.4 },
    { channel: 'paid_social', credits: 280, revenue: 16800, percentage: 11.8 },
    { channel: 'direct', credits: 250, revenue: 15000, percentage: 10.5 },
    { channel: 'referral', credits: 220, revenue: 13200, percentage: 9.2 },
    { channel: 'organic_social', credits: 180, revenue: 10800, percentage: 7.6 },
    { channel: 'display', credits: 150, revenue: 9000, percentage: 6.3 },
    { channel: 'affiliate', credits: 100, revenue: 6000, percentage: 4.2 },
    { channel: 'video', credits: 52, revenue: 3120, percentage: 2.2 }
  ]
};

// Funnel Data (Events)
const funnelData = {
  touchFilter: 'first_touch', // 'last_touch', 'assisted'
  stages: [
    {
      stage: 'Visits',
      total: 349402,
      byChannel: {
        paid_search: 87350, organic_search: 69880, email: 52410,
        paid_social: 41928, direct: 38434, referral: 27952,
        organic_social: 17470, display: 10482, affiliate: 2794, video: 702
      },
      conversionRate: null // First stage, no rate
    },
    {
      stage: 'Add to Cart',
      total: 37145,
      byChannel: {
        paid_search: 9286, organic_search: 7429, email: 5572,
        paid_social: 4457, direct: 4086, referral: 2972,
        organic_social: 1857, display: 1114, affiliate: 297, video: 75
      },
      conversionRate: 1284.8 // % from prior stage
    },
    {
      stage: 'Checkout Started',
      total: 5504,
      byChannel: {
        paid_search: 1376, organic_search: 1101, email: 825,
        paid_social: 660, direct: 605, referral: 440,
        organic_social: 275, display: 165, affiliate: 44, video: 13
      },
      conversionRate: 76.9
    },
    {
      stage: 'Purchase',
      total: 2382,
      byChannel: {
        paid_search: 596, organic_search: 476, email: 357,
        paid_social: 286, direct: 262, referral: 190,
        organic_social: 119, display: 71, affiliate: 19, video: 6
      },
      conversionRate: 56.3
    }
  ]
};
```

---

## File Structure

```
app/
├── controllers/
│   └── dashboard/
│       ├── main_controller.rb         # Main dashboard page (parses URL params)
│       ├── filters_controller.rb      # Turbo frame endpoint for filters
│       ├── conversions_controller.rb  # Turbo frame endpoint for conversions
│       └── events_controller.rb       # Turbo frame endpoint for funnel
├── services/
│   └── dashboard/
│       ├── conversion_data_service.rb # Queries attribution_credits (cached)
│       ├── funnel_data_service.rb     # Queries events + sessions (cached)
│       ├── comparison_data_service.rb # Multi-model comparison
│       └── filter_options_service.rb  # Dynamic filter options (channels, etc.)
├── views/
│   └── dashboard/
│       ├── main/
│       │   └── show.html.erb          # Main container with turbo-frames
│       ├── filters/
│       │   ├── show.html.erb          # Filters section
│       │   └── _skeleton.html.erb     # Loading skeleton for filters
│       ├── conversions/
│       │   ├── show.html.erb          # Conversions section
│       │   └── _skeleton.html.erb     # Loading skeleton
│       └── events/
│           ├── show.html.erb          # Events/funnel section
│           └── _skeleton.html.erb     # Loading skeleton
└── javascript/
    └── controllers/
        ├── dashboard_controller.js     # Main orchestrator
        ├── chart_controller.js         # Highcharts wrapper
        ├── filter_controller.js        # Filter interactions + Apply button
        ├── dropdown_controller.js      # Multi-select dropdown for channels
        └── comparison_controller.js    # Model comparison toggle
```

---

## Implementation Phases

### Phase 1: Prototype with Dummy Data (This Sprint)

**Goal**: Build full UI with hardcoded data, validate UX

**Deliverables**:
- [ ] Dashboard shell with Turbo Frames (filters, conversions, events)
- [ ] Skeleton loading states for all sections
- [ ] Filter bar with dropdown multi-select for channels
- [ ] **Apply button** pattern (no auto-apply)
- [ ] **URL param persistence** (bookmarkable filters)
- [ ] Conversions section (cards + bar chart)
- [ ] Events section (funnel chart with touch filter)
- [ ] Basic comparison mode (side-by-side)
- [ ] Stimulus controllers (filter, dropdown, chart, comparison)
- [ ] Highcharts integration

**Tech Notes**:
- Use `data-*` attributes for dummy data injection
- Charts render from inline JSON
- Turbo.visit() on Apply to update URL and reload
- No backend queries yet

### Phase 2: Wire Up Real Data

**Goal**: Replace dummy data with actual queries

**Deliverables**:
- [ ] Dashboard::ConversionDataService (queries attribution_credits)
- [ ] Dashboard::FunnelDataService (queries events + sessions)
- [ ] Dashboard::FilterOptionsService (dynamic channel list from DB)
- [ ] Turbo Frame endpoints return real data
- [ ] Continuous aggregate views for performance
- [ ] Date range filtering with URL params

### Phase 3: Caching & Performance

**Goal**: Production-ready dashboard with fast queries

**Deliverables**:
- [ ] **Rails.cache** for query results (Solid Cache, 5-15 min TTL)
- [ ] **Cache key** based on account + filter params
- [ ] **Cache invalidation** on event ingestion
- [ ] Fragment caching for chart HTML
- [ ] Continuous aggregates hourly refresh
- [ ] Manual refresh button for users

### Phase 4: Polish & Accessibility

**Goal**: Production-ready UX

**Deliverables**:
- [ ] Loading states and error handling
- [ ] Responsive design (mobile/tablet)
- [ ] Accessibility (ARIA labels, keyboard nav)
- [ ] Export functionality (CSV/PNG)

---

## Component Specifications

### Filter Bar

**Key behaviors**:
- Filters load via Turbo Frame (dynamic options from DB)
- No auto-apply; user must click "Apply" button
- Apply button triggers `Turbo.visit()` with new URL params
- Selected state visible in URL for bookmarking

```erb
<!-- app/views/dashboard/filters/show.html.erb -->
<turbo-frame id="filters-section">
  <div class="dashboard-filters" data-controller="filter">

    <!-- Date Range -->
    <div class="filter-group">
      <label class="filter-label">Date Range</label>
      <select data-filter-target="dateRange">
        <option value="7d" <%= 'selected' if params[:date_range] == '7d' %>>Last 7 days</option>
        <option value="30d" <%= 'selected' if params[:date_range] == '30d' %>>Last 30 days</option>
        <option value="90d" <%= 'selected' if params[:date_range] == '90d' %>>Last 90 days</option>
        <option value="custom">Custom</option>
      </select>
    </div>

    <!-- Attribution Model -->
    <div class="filter-group">
      <label class="filter-label">Attribution Model</label>
      <select data-filter-target="model">
        <option value="first_touch">First Touch</option>
        <option value="last_touch">Last Touch</option>
        <option value="linear" selected>Linear</option>
        <option value="time_decay">Time Decay</option>
        <option value="u_shaped">U-Shaped</option>
        <option value="w_shaped">W-Shaped</option>
        <option value="participation">Participation</option>
      </select>
    </div>

    <!-- Channels Dropdown (multi-select with checkboxes) -->
    <div class="filter-group" data-controller="dropdown">
      <label class="filter-label">Channels</label>
      <button type="button"
              class="dropdown-trigger"
              data-action="click->dropdown#toggle">
        <span data-dropdown-target="label">
          <%= selected_channels_label(params[:channels]) %>
        </span>
        <svg class="dropdown-chevron"><!-- chevron icon --></svg>
      </button>

      <div class="dropdown-menu" data-dropdown-target="menu" hidden>
        <label class="dropdown-item">
          <input type="checkbox"
                 data-action="change->dropdown#toggleAll"
                 data-dropdown-target="selectAll">
          <span>Select All</span>
        </label>
        <hr class="dropdown-divider">
        <% @available_channels.each do |channel| %>
          <label class="dropdown-item">
            <input type="checkbox"
                   value="<%= channel[:key] %>"
                   <%= 'checked' if channel_selected?(channel[:key], params[:channels]) %>
                   data-dropdown-target="checkbox"
                   data-action="change->dropdown#updateLabel">
            <span class="channel-dot" style="background: <%= channel[:color] %>"></span>
            <span><%= channel[:label] %></span>
          </label>
        <% end %>
      </div>
    </div>

    <!-- Compare Models Toggle -->
    <button type="button"
            data-action="click->comparison#toggle"
            class="btn-secondary btn-sm">
      Compare Models
    </button>

    <!-- APPLY BUTTON -->
    <button type="button"
            data-action="click->filter#apply"
            class="btn-primary">
      Apply
    </button>

  </div>
</turbo-frame>
```

### Filter Controller (Stimulus)

```javascript
// app/javascript/controllers/filter_controller.js
import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["dateRange", "model"]

  apply() {
    // Build URL with current filter state
    const params = new URLSearchParams()

    params.set("date_range", this.dateRangeTarget.value)
    params.set("model", this.modelTarget.value)

    // Get selected channels from dropdown controller
    const channels = this.#getSelectedChannels()
    if (channels.length > 0) {
      params.set("channels", channels.join(","))
    }

    // Navigate with Turbo (updates URL, reloads page with new params)
    const url = `${window.location.pathname}?${params.toString()}`
    Turbo.visit(url)
  }

  #getSelectedChannels() {
    const checkboxes = document.querySelectorAll('[data-dropdown-target="checkbox"]:checked')
    return Array.from(checkboxes).map(cb => cb.value)
  }
}
```

### Skeleton Loading Components

```erb
<!-- app/views/dashboard/filters/_skeleton.html.erb -->
<div class="dashboard-filters animate-pulse">
  <div class="filter-group">
    <div class="skeleton-text w-20 h-4 mb-2"></div>
    <div class="skeleton-box w-32 h-10"></div>
  </div>
  <div class="filter-group">
    <div class="skeleton-text w-24 h-4 mb-2"></div>
    <div class="skeleton-box w-40 h-10"></div>
  </div>
  <div class="filter-group">
    <div class="skeleton-text w-16 h-4 mb-2"></div>
    <div class="skeleton-box w-36 h-10"></div>
  </div>
  <div class="skeleton-box w-24 h-10"></div>
</div>
```

```erb
<!-- app/views/dashboard/conversions/_skeleton.html.erb -->
<div class="dashboard-section animate-pulse">
  <h2 class="section-title skeleton-text w-32"></h2>

  <!-- Metric Cards Skeleton -->
  <div class="grid grid-cols-2 gap-4 mb-6">
    <div class="metric-card">
      <div class="skeleton-text w-24 h-4 mb-2"></div>
      <div class="skeleton-text w-16 h-8"></div>
    </div>
    <div class="metric-card">
      <div class="skeleton-text w-24 h-4 mb-2"></div>
      <div class="skeleton-text w-20 h-8"></div>
    </div>
  </div>

  <!-- Chart Skeleton -->
  <div class="chart-container">
    <div class="skeleton-chart h-64"></div>
  </div>
</div>
```

### Turbo Frame Structure

```erb
<!-- app/views/dashboard/main/show.html.erb -->
<div class="dashboard-container" data-controller="dashboard">

  <!-- Filters Section (loads via Turbo, has dynamic options) -->
  <turbo-frame id="filters-section"
    src="<%= dashboard_filters_path(request.query_parameters) %>"
    loading="eager">
    <%= render 'dashboard/filters/skeleton' %>
  </turbo-frame>

  <!-- Conversions Section -->
  <turbo-frame id="conversions-section"
    src="<%= dashboard_conversions_path(request.query_parameters) %>"
    loading="lazy">
    <%= render 'dashboard/conversions/skeleton' %>
  </turbo-frame>

  <!-- Events Section -->
  <turbo-frame id="events-section"
    src="<%= dashboard_events_path(request.query_parameters) %>"
    loading="lazy">
    <%= render 'dashboard/events/skeleton' %>
  </turbo-frame>

</div>
```

**Note**: `request.query_parameters` passes current URL params to each frame endpoint, ensuring filters are applied consistently across all sections.

---

## Research Sources

- [Adobe Analytics Attribution IQ](https://www.adobe.com/content/dam/dx/us/en/products/analytics/marketing-attribution/pdfs/54658.en.analytics.tipsheet.tips-tricks_attribution-IQ.pdf) - Multi-model comparison patterns
- [Google Analytics Model Comparison Tool](https://support.google.com/analytics/answer/6148697?hl=en) - Compare up to 3 models
- [Salesforce Multi-Touch Attribution](https://www.salesforce.com/marketing/multi-touch-attribution/) - Best practices
- [Databox Marketing Attribution Dashboard](https://databox.com/marketing-attribution-dashboard) - Dashboard design patterns
- [Chartio Funnel Chart Guide](https://chartio.com/learn/charts/funnel-chart-complete-guide/) - Stacked bar alternatives
- [GoRails Highcharts in Rails](https://gorails.com/forum/implementing-highcharts-in-ror) - Rails integration patterns
- [Pencil & Paper Dashboard UX Patterns](https://www.pencilandpaper.io/articles/ux-pattern-analysis-data-dashboards) - Filter and hierarchy patterns

---

## Open Questions

1. **Custom date range picker**: Should we build custom or use a library (flatpickr)?
2. **Funnel stage configuration**: Hardcoded stages or account-configurable?
3. **Export format**: PDF, PNG, or CSV? All three?
4. **Mobile experience**: Simplified charts or full responsive?

## Resolved Decisions

| Decision | Resolution |
|----------|------------|
| Caching strategy | Multi-layer: Solid Cache + continuous aggregates + fragment caching |
| Filter apply behavior | Explicit "Apply" button, no auto-apply |
| URL state | Filters persist in URL params for bookmarkability |
| Channel filter UI | Dropdown with multi-select checkboxes |
| Filters loading | Via Turbo Frame (dynamic options from DB) |

---

## Next Steps

1. **Review & Approval**: Get feedback on this spec
2. **Design Mockups**: Create high-fidelity Figma mockups (optional)
3. **Start Phase 1**: Build prototype with dummy data
4. **Iterate**: Gather feedback, refine before wiring real data

---

**See also**:
- `lib/docs/architecture/attribution_methodology.md` - Attribution model definitions
- `lib/docs/architecture/conversion_funnel_analysis.md` - Funnel analysis concepts
- `lib/docs/architecture/channel_vs_utm_attribution.md` - Channel taxonomy
- `docs/design/visual_design_system.md` - Design tokens and patterns
