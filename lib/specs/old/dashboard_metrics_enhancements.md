# Spec: Dashboard Metrics Enhancements

**Status**: ✅ COMPLETE
**Last Updated**: 2026-01-10

## Implementation Status

### Feature 1: Avg Days to Convert ✅ COMPLETE
- `avg_days_to_convert` implemented in `TotalsQuery`
- `avg_days_by_channel` in `JourneyMetricsByChannel`
- `avg_days` in `ByChannelQuery` and `ByConversionNameQuery`

### Feature 2: Metric-Responsive Charts ✅ COMPLETE
- ✅ Channel chart responds to metric selection
- ✅ Dimension chart responds to metric selection
- ✅ Time Series Chart responds to metric selection (credits, revenue, conversions)

---

## Overview

Two enhancements to the conversions dashboard:
1. **Avg Days to Convert** - Calculate and display the average time from first touch to conversion
2. **Metric-responsive charts** - Make both the "X by Channel" and "X by [Dimension]" charts respond to the selected metric, including avg_days

---

## Feature 1: Avg Days to Convert

### Background

Currently, `avg_days_to_convert` in `TotalsQuery` returns `nil` (TODO stub). This metric should calculate the average number of days between a visitor's first session and their conversion.

### Data Model

```
Session (started_at)
    ↓
AttributionCredit (session_id, conversion_id)
    ↓
Conversion (converted_at, journey_session_ids[])
```

**Key fields:**
- `sessions.started_at` - When the session started
- `conversions.converted_at` - When the conversion happened
- `conversions.journey_session_ids` - Array of session IDs in the conversion journey

### Calculation Logic

For each conversion in scope:
1. Find the earliest session `started_at` among the conversion's journey sessions
2. Calculate `(converted_at - earliest_started_at)` in days
3. Average across all conversions

**SQL approach:**
```sql
SELECT
  AVG(EXTRACT(EPOCH FROM (c.converted_at - first_session.started_at)) / 86400.0) as avg_days
FROM (
  SELECT DISTINCT conversion_id FROM attribution_credits WHERE ...scope...
) ac
INNER JOIN conversions c ON c.id = ac.conversion_id
INNER JOIN LATERAL (
  SELECT MIN(s.started_at) as started_at
  FROM sessions s
  WHERE s.id = ANY(c.journey_session_ids)
) first_session ON true
```

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| No conversions in scope | Return `nil` |
| Same-session conversion | 0 days (not excluded) |
| Missing journey_session_ids | Skip conversion from calculation |
| Empty sessions array | Skip conversion from calculation |

### Implementation Location

- File: `app/services/dashboard/queries/totals_query.rb`
- Method: `avg_days_to_convert` (replace TODO stub)

### Test Cases

1. **Single conversion with multi-day journey** - Conversion with first session 5 days before = 5.0
2. **Multiple conversions** - Two conversions (3 days, 7 days) = 5.0 average
3. **Same-session conversion** - First session same as conversion = 0.0
4. **Empty data** - No conversions = `nil`
5. **Fractional days** - Session at 12:00, conversion at 18:00 same day = 0.25 days

---

## Feature 2: Metric-Responsive Charts (Including Avg Days)

### Background

Both charts on the dashboard should respond to the selected metric:
1. **"X by Channel"** - Currently works for credits, revenue, avg_channels, avg_visits
2. **"X by [Dimension]"** - Currently always shows credits

Both need to support `avg_days` as a metric option.

### Current Behavior

**Channel Chart (partially working):**
- Supports: credits, revenue, avg_channels, avg_visits
- Missing: avg_days

**Dimension Chart (not working):**
```erb
<div data-chart-metric-value="credits">  <!-- Always "credits" -->
```

### Desired Behavior

When user selects the "Avg Days" KPI card:
1. Both charts should display avg_days data
2. Y-axis should show "Avg Days"
3. Values formatted as decimal days (e.g., "4.2")

### Metric to Chart Metric Mapping

| Selected Metric | Chart Metric | Data Key |
|-----------------|--------------|----------|
| conversions | credits | `row[:credits]` |
| revenue | revenue | `row[:revenue]` |
| aov | revenue | `row[:revenue]` |
| avg_channels | avg_channels | `row[:avg_channels]` |
| avg_visits | avg_visits | `row[:avg_visits]` |
| avg_days | avg_days | `row[:avg_days]` |

### Implementation Changes

#### 1. ByChannelQuery Enhancement

Add `avg_days` to channel rows:

```ruby
# app/services/dashboard/queries/by_channel_query.rb
def build_channel_row(row)
  {
    channel: row.channel,
    credits: row.total_credits.to_f,
    revenue: row.total_revenue.to_f,
    percentage: percentage(row.total_credits),
    avg_channels: journey_metrics.avg_channels_by_channel[row.channel],
    avg_visits: journey_metrics.avg_visits_by_channel[row.channel],
    avg_days: journey_metrics.avg_days_by_channel[row.channel]  # NEW
  }
end
```

#### 2. ByConversionNameQuery Enhancement

Add avg_channels, avg_visits, avg_days to the returned data:

```ruby
# app/services/dashboard/queries/by_conversion_name_query.rb
def build_row(row)
  {
    channel: row.dimension_value || "(not set)",
    credits: row.total_credits.to_f,
    revenue: row.total_revenue.to_f,
    conversion_count: row.conversion_count,
    percentage: percentage(row.total_credits),
    avg_channels: calculate_avg_channels(row),   # NEW
    avg_visits: calculate_avg_visits(row),       # NEW
    avg_days: calculate_avg_days(row)            # NEW
  }
end
```

#### 3. JourneyMetricsByChannel Enhancement

Add `avg_days_by_channel` calculation:

```ruby
# app/services/dashboard/queries/journey_metrics_by_channel.rb
def avg_days_by_channel
  @avg_days_by_channel ||= calculate_avg_days_by_channel
end

def calculate_avg_days_by_channel
  # For each channel, calculate avg days from first session to conversion
end
```

#### 4. View Updates

**_by_conversion_name_chart.html.erb:**
```erb
<!-- Before -->
<h3 class="...">Conversions by</h3>
<div data-chart-metric-value="credits">

<!-- After -->
<h3 class="..."><%= chart_title %> by</h3>
<div data-chart-metric-value="<%= chart_metric %>">
```

**_full_dashboard.html.erb (already correct for channel chart):**
- Just ensure avg_days mapping is included in `chart_metric` case statement

#### 5. chart_controller.js Enhancement

Ensure the metricConfigs includes avg_days (check if already present):

```javascript
const metricConfigs = {
  // ... existing configs ...
  avg_days: {
    dataKey: "avg_days",
    yAxisTitle: "Avg Days",
    formatValue: (y) => Highcharts.numberFormat(y, 1),
    drilldownable: false
  }
}
```

### Test Cases

1. **Channel chart with avg_days metric** - Shows avg_days per channel
2. **Dimension chart with avg_days metric** - Shows avg_days per dimension value
3. **Default metric** - Shows credits when no metric selected
4. **Revenue metric** - Shows revenue values with $ formatting
5. **Avg channels metric** - Shows average channels per dimension
6. **Avg visits metric** - Shows average visits per dimension

---

## Implementation Order

1. Write failing test for `avg_days_to_convert` in TotalsQuery
2. Implement `avg_days_to_convert` in TotalsQuery
3. Add `avg_days_by_channel` to JourneyMetricsByChannel
4. Update ByChannelQuery to include avg_days
5. Write failing test for ByConversionNameQuery journey metrics
6. Add avg_channels, avg_visits, avg_days to ByConversionNameQuery
7. Update _by_conversion_name_chart view to pass metric and dynamic title
8. Verify chart_controller.js has avg_days config
9. Run all tests and verify in browser

---

## Files to Modify

| File | Change |
|------|--------|
| `app/services/dashboard/queries/totals_query.rb` | Implement `avg_days_to_convert` |
| `app/services/dashboard/queries/journey_metrics_by_channel.rb` | Add `avg_days_by_channel` |
| `app/services/dashboard/queries/by_channel_query.rb` | Include avg_days in row |
| `app/services/dashboard/queries/by_conversion_name_query.rb` | Add journey metrics |
| `app/views/dashboard/conversions/_by_conversion_name_chart.html.erb` | Pass metric, update title |
| `app/javascript/controllers/chart_controller.js` | Verify avg_days config exists |
| `test/services/dashboard/queries/totals_query_test.rb` | Add avg_days tests |
| `test/services/dashboard/queries/by_conversion_name_query_test.rb` | Add journey metrics tests |
