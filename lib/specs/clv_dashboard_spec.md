# Spec: Customer Lifetime Value (CLV) Dashboard

## Overview

Add a CLV view mode to the existing conversions dashboard, toggled via a switch. This view shows customer-centric metrics rather than transaction-centric metrics, enabling users to understand which acquisition channels bring the most valuable long-term customers.

**Prerequisite:** CLV mode requires the recurring revenue attribution feature (`is_acquisition` + `inherit_acquisition` flags). If users haven't implemented this, show guidance on how to enable CLV tracking.

---

## Core Concept: Date Filter Meaning

| View Mode | Date Filter Meaning |
|-----------|---------------------|
| **Standard Conversions** | "Show conversions that happened in this date range" |
| **CLV Mode** | "Show customers **acquired** in this date range, with their **full lifetime** value" |

**Critical distinction:** In CLV mode, date range = **cohort selection** (acquisition period), not revenue period.

**Example:**
- Date range: "Last 30 days"
- Standard mode: Shows all conversions from last 30 days
- CLV mode: Shows customers whose `is_acquisition` conversion was in last 30 days, but includes ALL their subsequent revenue

---

## Requirements

### Data Requirements

CLV mode **requires identified customers** with the acquisition attribution flow:

1. User must have called `identify(user_id: "...", visitor_id: "...")`
2. User must have tracked an acquisition conversion: `conversion(user_id: "...", is_acquisition: true)`
3. Subsequent conversions should use `inherit_acquisition: true`

**If no CLV data exists:** Show an empty state with setup guidance (see UI section).

---

## UI Design

### Toggle Switch

Add toggle in conversions dashboard header:

```
┌─────────────────────────────────────────────────────────────┐
│  Conversions                                                 │
│                                                              │
│  [Transactions ◉] [Customer LTV ○]     ← Toggle switch      │
└─────────────────────────────────────────────────────────────┘
```

### CLV Dashboard Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Customer LTV                                                │
│                                                              │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Acquisition Period: [Last 30 days ▼]                    ││
│  │ 234 customers acquired · 89% of conversions identified  ││
│  └─────────────────────────────────────────────────────────┘│
│                                                              │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐    │
│  │ CLV  │ │Cust. │ │Purch.│ │ Rev  │ │ Dur. │ │ Freq │    │
│  │$847  │ │ 234  │ │ 892  │ │$198K │ │ 94d  │ │ 3.8x │    │
│  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘    │
│                                                              │
│  [Smiling Curve]                      [Cohort Analysis]     │
│  ┌────────────────────────┐          ┌────────────────────┐ │
│  │  Avg Rev/Customer      │          │ Month │ M1  │ M2   │ │
│  │  by Lifecycle Month    │          │ Oct   │$120 │$180  │ │
│  │     (see below)        │          │ Nov   │$115 │$165  │ │
│  └────────────────────────┘          └────────────────────┘ │
│                                                              │
│  [CLV by Acquisition Channel]                               │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ Referrals      ████████████████████  $1,247 avg CLV     ││
│  │ Organic        ███████████████       $892 avg CLV       ││
│  │ Google Ads     ██████████            $634 avg CLV       ││
│  │ Facebook       ██████                $412 avg CLV       ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### Empty State (No CLV Data)

When no `is_acquisition` conversions exist:

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│  📊 Enable Customer Lifetime Value Tracking                  │
│                                                              │
│  CLV analytics require identifying customers and marking     │
│  acquisition events. Here's how to set it up:               │
│                                                              │
│  1. Identify your users on signup/login:                    │
│     mbuzz.identify(user_id: "user_123", visitor_id: vid)    │
│                                                              │
│  2. Mark signups as acquisition conversions:                │
│     mbuzz.conversion(                                        │
│       user_id: "user_123",                                  │
│       conversion_type: "signup",                            │
│       is_acquisition: true                                  │
│     )                                                        │
│                                                              │
│  3. Track payments with inherited attribution:              │
│     mbuzz.conversion(                                        │
│       user_id: "user_123",                                  │
│       conversion_type: "payment",                           │
│       revenue: 49.00,                                       │
│       inherit_acquisition: true                             │
│     )                                                        │
│                                                              │
│  [View Documentation →]                                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Metrics

### KPI Cards (6 metrics)

| Metric | Label | Calculation | Format |
|--------|-------|-------------|--------|
| **CLV** | Avg CLV | `SUM(revenue) / COUNT(DISTINCT identity_id)` | Currency |
| **Customers** | Customers | `COUNT(DISTINCT identity_id)` where `is_acquisition = true` in date range | Number |
| **Purchases** | Purchases | `COUNT(conversions)` for acquired customers | Number |
| **Revenue** | Total Revenue | `SUM(revenue)` for acquired customers | Currency |
| **Avg Duration** | Avg Lifespan | `AVG(last_conversion - first_conversion)` in days | Days |
| **Repurchase Freq** | Purchases/Customer | `COUNT(conversions) / COUNT(DISTINCT identity_id)` | Decimal (1.0x) |

### Additional Metrics (for later)

- **Repeat Rate**: % of customers with >1 conversion
- **90-day LTV**: Revenue in first 90 days (standardized comparison)
- **Churn Rate**: % of customers with no activity in X days

---

## Charts

### 1. Smiling Curve (Revenue per Customer by Lifecycle Month)

The "smiling curve" shows **average revenue per customer** for each month of their customer lifecycle, broken down by acquisition channel.

**Why it "smiles":**
- **Month 1 (high):** All customers make their first purchase
- **Months 2-6 (dip):** Many customers churn, lowering average
- **Months 12+ (rise):** Loyal customers who remain become more valuable (upgrades, higher frequency)

**X-axis:** Lifecycle month (M1, M2, M3, ... M12+)
**Y-axis:** Average revenue per customer that month
**Lines:** One per acquisition channel

```
Avg Rev/
Customer
   │
$80│ ●                                              ●───●
   │  ╲                                          ╱
$60│   ╲                                      ╱
   │    ╲    Referrals                     ╱
$40│     ╲──────────────────────────────╱
   │       ╲                          ╱
$20│        ╲    Facebook          ╱
   │         ╲────────────────────╱
$0 │──────────────────────────────────────────────────
   │  M1   M2   M3   M4   M5   M6   M9   M12  M18  M24
                  Lifecycle Month
```

**Interpretation:**
- Higher curve = better channel (more valuable customers)
- Deeper dip = more churn from that channel
- Steeper rise = better expansion/loyalty from that channel
- Referrals often show the best "smile" (loyal from day 1)

**Data query:**
```sql
SELECT
  ac.channel as acquisition_channel,
  EXTRACT(MONTH FROM AGE(c.converted_at, acq.converted_at)) + 1 as lifecycle_month,
  AVG(c.revenue) as avg_revenue_per_customer
FROM conversions c
JOIN conversions acq ON c.identity_id = acq.identity_id AND acq.is_acquisition = true
JOIN attribution_credits ac ON acq.id = ac.conversion_id
WHERE acq.converted_at BETWEEN :start_date AND :end_date
  AND ac.attribution_model_id = :model_id
GROUP BY ac.channel, lifecycle_month
ORDER BY ac.channel, lifecycle_month
```

### 2. Cohort Analysis Heatmap

Shows cumulative LTV progression by acquisition cohort (month).

**Rows:** Acquisition month cohort
**Columns:** Months since acquisition (M0, M1, M2, ...)
**Cells:** Cumulative LTV at that point

```
         │  M0   │  M1   │  M2   │  M3   │  M6   │  M12  │
─────────┼───────┼───────┼───────┼───────┼───────┼───────┤
Oct 2024 │  $49  │  $82  │ $124  │ $156  │ $203  │ $287  │
Nov 2024 │  $52  │  $89  │ $131  │ $168  │  —    │  —    │
Dec 2024 │  $47  │  $78  │  —    │  —    │  —    │  —    │
```

**Color coding:** Gradient from light (low) to dark (high) to highlight best-performing cohorts.

**Use cases:**
- Compare cohort quality over time (is product improving?)
- Identify seasonal patterns (Q4 acquisitions vs Q1)
- Project future revenue from recent cohorts

### 3. CLV by Acquisition Channel

Bar chart showing average CLV per customer by the channel that acquired them.

**Attribution:** Uses the `is_acquisition` conversion's attributed channel (respects selected attribution model).

```
Referrals      ████████████████████  $1,247  (87 customers)
Organic        ███████████████       $892    (124 customers)
Google Ads     ██████████            $634    (203 customers)
Facebook       ██████                $412    (156 customers)
```

---

## Attribution Model Behavior

All attribution models remain available for comparison in CLV mode. The key difference:

**Standard mode:** Attribution model determines how credit is distributed across channels for each conversion.

**CLV mode:** Attribution model determines which channel gets credit for **acquiring** the customer (based on the `is_acquisition` conversion), and ALL subsequent revenue for that customer is attributed to that acquisition channel.

This means:
- First-touch model → First touchpoint before acquisition gets all LTV
- Last-touch model → Last touchpoint before acquisition gets all LTV
- Linear model → LTV distributed across pre-acquisition touchpoints

The `inherit_acquisition` conversions inherit the attribution from the acquisition conversion, so the model selection affects which channel "owns" the customer.

---

## Data Architecture

### Query Strategy

CLV queries group by `identity_id` rather than `conversion_id`:

```ruby
# Pseudo-query for CLV totals
def clv_totals(account, date_range, attribution_model)
  # Step 1: Find acquisition conversions in date range
  acquisition_conversions = account.conversions
    .where(is_acquisition: true)
    .where(converted_at: date_range)
    .pluck(:identity_id)

  # Step 2: Get ALL conversions for those customers (no date filter)
  customer_conversions = account.conversions
    .where(identity_id: acquisition_conversions)

  # Step 3: Aggregate by customer
  customer_conversions
    .group(:identity_id)
    .select(
      'identity_id',
      'COUNT(*) as purchases',
      'SUM(revenue) as lifetime_revenue',
      'MIN(converted_at) as first_conversion',
      'MAX(converted_at) as last_conversion'
    )
end
```

### New Service: `Dashboard::ClvDataService`

```ruby
module Dashboard
  class ClvDataService < ApplicationService
    def initialize(account, filter_params)
      @account = account
      @filter_params = filter_params
    end

    def query_data
      {
        totals: clv_totals,
        by_channel: clv_by_channel,
        smiling_curve: smiling_curve,
        cohort_analysis: cohort_analysis,
        coverage: identity_coverage
      }
    end

    private

    def acquired_identity_ids
      @acquired_identity_ids ||= @account.conversions
        .where(is_acquisition: true)
        .where(converted_at: date_range)
        .where(is_test: test_mode?)
        .pluck(:identity_id)
        .compact
    end

    def clv_totals
      # Return CLV metrics for acquired customers
    end

    def clv_by_channel
      # Group by acquisition channel, sum lifetime revenue
    end

    def smiling_curve
      # Average revenue per customer by lifecycle month, by channel
    end

    def cohort_analysis
      # Cohort x Month matrix with cumulative LTV
    end

    def identity_coverage
      # % of conversions with identity_id
      total = @account.conversions.where(converted_at: date_range).count
      identified = @account.conversions.where(converted_at: date_range).where.not(identity_id: nil).count
      { total: total, identified: identified, percentage: (identified.to_f / total * 100).round(1) }
    end
  end
end
```

### New Query Classes

```
app/services/dashboard/queries/
├── clv_totals_query.rb
├── clv_by_channel_query.rb
├── smiling_curve_query.rb
└── cohort_analysis_query.rb
```

---

## Implementation Checklist

### Phase 1: Backend

- [ ] Create `Dashboard::ClvDataService`
- [ ] Create `ClvTotalsQuery` - aggregate CLV metrics
- [ ] Create `ClvByChannelQuery` - CLV grouped by acquisition channel
- [ ] Create `SmilingCurveQuery` - avg revenue per customer by lifecycle month by channel
- [ ] Create `CohortAnalysisQuery` - cohort x month matrix
- [ ] Add `clv_mode` to filter params in `Dashboard::BaseController`
- [ ] Add route `PATCH /dashboard/clv_mode` (follow `view_mode` pattern)
- [ ] Write tests for all queries

### Phase 2: Frontend

- [ ] Add CLV/Transactions toggle switch to conversions header
- [ ] Create `_clv_dashboard.html.erb` partial
- [ ] Create `_clv_kpi_cards.html.erb` partial (6 metrics)
- [ ] Update date range label to "Acquisition Period" in CLV mode
- [ ] Add coverage indicator ("89% of conversions identified")
- [ ] Create empty state partial with setup instructions

### Phase 3: Charts

- [ ] Create smiling curve chart (Highcharts multi-line)
- [ ] Create cohort analysis heatmap (Highcharts heatmap or HTML table)
- [ ] Update CLV by channel bar chart
- [ ] Add appropriate tooltips and legends

### Phase 4: Polish

- [ ] Add loading states for CLV data
- [ ] Implement caching (5-minute TTL, same pattern as conversions)
- [ ] Add Turbo frame for CLV view switching
- [ ] Test with real data scenarios
- [ ] Update API documentation

---

## Files to Create/Modify

### New Files
- `app/services/dashboard/clv_data_service.rb`
- `app/services/dashboard/queries/clv_totals_query.rb`
- `app/services/dashboard/queries/clv_by_channel_query.rb`
- `app/services/dashboard/queries/smiling_curve_query.rb`
- `app/services/dashboard/queries/cohort_analysis_query.rb`
- `app/views/dashboard/conversions/_clv_dashboard.html.erb`
- `app/views/dashboard/conversions/_clv_kpi_cards.html.erb`
- `app/views/dashboard/conversions/_clv_empty_state.html.erb`
- `test/services/dashboard/clv_data_service_test.rb`
- `test/services/dashboard/queries/clv_*_test.rb`

### Modified Files
- `app/controllers/dashboard/base_controller.rb` - Add clv_mode to filter_params
- `app/controllers/dashboard/conversions_controller.rb` - Handle CLV mode
- `app/views/dashboard/conversions/show.html.erb` - Add toggle, conditional rendering
- `app/views/dashboard/conversions/_full_dashboard.html.erb` - Integrate toggle
- `config/routes.rb` - Add clv_mode route (if needed)

---

## Edge Cases

1. **No acquisition conversions** → Show empty state with setup guide
2. **Acquisition but no subsequent conversions** → Show CLV = first purchase value
3. **Multiple acquisition conversions for same identity** → Use most recent (or first?)
4. **Identity with 0 revenue conversions** → Include in customer count, $0 CLV
5. **Very recent acquisitions** → LTV will be low; consider 90-day LTV metric for comparison

---

## Future Enhancements

1. **Predicted LTV** - ML-based LTV prediction for recent cohorts
2. **CLV:CAC Ratio** - If CAC data becomes available
3. **Segment filtering** - CLV by customer segment (plan, region, etc.)
4. **Export** - CSV export of cohort data
5. **Alerts** - Notify when CLV drops below threshold

---

## Sources

- [Sequoia - Retention](https://articles.sequoiacap.com/retention)
- [Wicked Reports - Cohort and LTV Reporting](https://help.wickedreports.com/guide-to-cohort-and-customer-lifetime-value-reporting)
- [Triple Whale - Customer Cohorts](https://kb.triplewhale.com/en/articles/5725663-customer-cohorts)
- [AppsFlyer - User Acquisition LTV Dashboard](https://support.appsflyer.com/hc/en-us/articles/360014697157-Overview-dashboard-user-acquisition-and-retargeting-LTV)
- [Point Nine - Cohort Analysis in SaaS](https://medium.com/point-nine-news/the-p9-guide-to-cohort-analysis-in-saas-v0-9-63ce366ab427)
- [Churnkey - Retention Curves](https://churnkey.co/blog/retention-curves/)
