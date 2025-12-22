# Dashboard Metrics Bug Assessment

**Status**: Investigation Complete
**Date**: 2025-12-23
**Priority**: High

---

## Summary

Three bugs were identified in the Conversions Dashboard metrics, plus a feature requirement for the "Conversions by X" chart:

| Issue | Current Behavior | Expected Behavior |
|-------|------------------|-------------------|
| Avg Visits | First Touch: 1.0, U-Shaped: 28.8 | Should be same across models |
| Avg Days | Shows "—" (null) | Should show actual average |
| Decimal Precision | 503.0774 conversions | 503.1 (one decimal place) |
| Conversions by X | Gray bar, no breakdown | Stacked bar with channel colors |

---

## Bug 1: Avg Visits Shows Different Values Per Model

### Observed Behavior
- **First Touch**: 1.0 avg visits
- **U-Shaped**: 28.8 avg visits

This doesn't make sense—the number of visits in a customer journey should be the same regardless of which attribution model is used.

### Root Cause Analysis

**Location**: `app/services/dashboard/queries/totals_query.rb:97-101`

```ruby
def visits_per_conversion
  @visits_per_conversion ||= scope
    .group(:conversion_id)
    .count
end
```

**Problem**: This counts `attribution_credits` per conversion, NOT actual visits/sessions.

Attribution models create different numbers of credits:
- **First Touch**: Creates 1 credit per conversion (only first touchpoint)
- **Last Touch**: Creates 1 credit per conversion (only last touchpoint)
- **Linear**: Creates n credits per conversion (1 per touchpoint)
- **U-Shaped**: Creates n credits per conversion (1 per touchpoint)
- **Participation**: Creates n credits per conversion (1 per unique channel)

So when you query `scope.group(:conversion_id).count`, you're counting attribution credits, which varies by model.

### Correct Calculation

"Avg Visits" should measure the number of sessions in the customer journey BEFORE conversion. This data is stored in `conversions.journey_session_ids` (a PostgreSQL array of session IDs).

**Fix**:

```ruby
def visits_per_conversion
  @visits_per_conversion ||= calculate_visits_per_conversion
end

def calculate_visits_per_conversion
  conversion_ids = scope.distinct.pluck(:conversion_id)
  return {} if conversion_ids.empty?

  Conversion
    .where(id: conversion_ids)
    .where.not(journey_session_ids: [])
    .pluck(:id, Arel.sql("ARRAY_LENGTH(journey_session_ids, 1)"))
    .to_h
end
```

This queries the actual journey length from the `journey_session_ids` array, which is model-independent.

### Affected Files
- `app/services/dashboard/queries/totals_query.rb` - `visits_per_conversion` method
- `app/services/dashboard/queries/journey_metrics_by_channel.rb` - `visits_per_conversion` method
- `app/services/dashboard/queries/by_conversion_name_query.rb` - `visits_per_conversion` method
- `app/services/dashboard/queries/by_channel_query.rb` - uses `JourneyMetricsByChannel`

---

## Bug 2: Avg Days Shows "—" (Null)

### Observed Behavior
- Both First Touch and U-Shaped show "—" for Avg Days
- Expected: Average days from first touch to conversion

### Root Cause Analysis

**Location**: `app/services/dashboard/queries/totals_query.rb:50-74`

```ruby
def avg_days_to_convert
  return nil if conversion_count.zero?

  days = days_per_conversion
  return nil if days.empty?  # <-- This returns nil if empty

  (days.sum / days.size).round(1)
end

def calculate_days_per_conversion
  conversion_ids = scope.distinct.pluck(:conversion_id)
  return [] if conversion_ids.empty?

  Conversion
    .where(id: conversion_ids)
    .where.not(journey_session_ids: [])  # <-- Filters out conversions with empty array
    .joins(
      "INNER JOIN LATERAL (
        SELECT MIN(s.started_at) as first_session_at
        FROM sessions s
        WHERE s.id = ANY(conversions.journey_session_ids)
      ) first_session ON true"
    )
    .pluck(...)
    .compact
    .map(&:to_f)
end
```

**Possible causes**:
1. **Empty `journey_session_ids`**: Conversions may have `[]` which are filtered out
2. **Session IDs don't exist**: The lateral join may fail to find sessions
3. **Null values**: The pluck may return nulls that `.compact` removes

### Diagnosis Steps

Check production data:

```sql
-- Count conversions with empty journey_session_ids
SELECT
  COUNT(*) FILTER (WHERE journey_session_ids = '{}') as empty_journey,
  COUNT(*) FILTER (WHERE journey_session_ids != '{}') as has_journey,
  COUNT(*) as total
FROM conversions
WHERE account_id = <your_account_id>;

-- Check if sessions exist for journey_session_ids
SELECT c.id, c.journey_session_ids,
  (SELECT COUNT(*) FROM sessions s WHERE s.id = ANY(c.journey_session_ids)) as found_sessions
FROM conversions c
WHERE account_id = <your_account_id>
AND journey_session_ids != '{}';
```

### Likely Fix

If most conversions have empty `journey_session_ids`, the root cause is in the conversion creation flow—it's not populating the journey. Need to verify the attribution calculation is setting this field.

If sessions exist but the lateral join fails, may need to handle timezone differences or session cleanup.

---

## Bug 3: Too Many Decimal Places

### Observed Behavior
- Conversions: `503.0774` (should be `503.1`)
- Revenue: `$326,763` (OK - currency already uses precision: 0)
- Avg Order Value: `$638` (OK)

### Root Cause Analysis

**Location**: `app/helpers/dashboard_helper.rb:13-17`

```ruby
METRIC_FORMATTERS = {
  currency: ->(v, h) { h.number_to_currency(v, precision: 0) },
  percentage: ->(v, _) { "#{v}%" },
  number: ->(v, h) { h.number_with_delimiter(v) }  # <-- No precision control
}.freeze
```

The `number` formatter uses `number_with_delimiter` which preserves all decimal places.

### Fix

```ruby
METRIC_FORMATTERS = {
  currency: ->(v, h) { h.number_to_currency(v, precision: 0) },
  percentage: ->(v, _) { "#{v}%" },
  number: ->(v, h) { h.number_with_delimiter(v.is_a?(Float) ? v.round(1) : v) }
}.freeze
```

Or round in the query:

```ruby
def sum_credits
  @sum_credits ||= scope.sum(:credit).to_f.round(1)
end
```

### Affected Views
- `_kpi_card_content.html.erb` - displays `format_metric(value)`
- Charts - `{y:.1f}` format is already correct in chart_controller.js

---

## Feature: Conversions by X Chart - Channel Color Coding

### Current Behavior
- Shows a single gray bar per conversion name/type
- No breakdown by channel
- Cannot see which channels drive each conversion type

### Requirement

The "Conversions by X" chart should be a **stacked bar chart** with channel breakdown:

```
Estimate Accepted  |████████████████████████████████████|  503.1
                   |[Direct 149.4][Referral 128.6][Paid Search 123.1][Organic 83.0][Other 19.0]|

Free Trial         |████████████████████|  287.3
                   |[Organic 120.2][Direct 89.1][...]|
```

### Implementation Approach

#### 1. Backend Changes

**File**: `app/services/dashboard/queries/by_conversion_name_query.rb`

Add channel breakdown to the query:

```ruby
def call
  return [] if total_credits.zero?

  aggregated_data
    .map { |row| build_row(row) }
    .sort_by { |row| -row[:credits] }
    .first(limit)
end

# Add new method for channel breakdown
def by_channel_breakdown
  scope
    .joins(:conversion)
    .group(group_expression, :channel)
    .select(
      "#{group_expression} as dimension_value",
      :channel,
      "SUM(credit) as total_credits"
    )
    .group_by(&:dimension_value)
    .transform_values do |rows|
      rows.map { |r| { channel: r.channel, credits: r.total_credits.to_f } }
           .sort_by { |r| -r[:credits] }
    end
end

def build_row(row)
  dimension_value = row.dimension_value || "(not set)"

  {
    channel: dimension_value,
    credits: row.total_credits.to_f,
    revenue: row.total_revenue.to_f,
    # ... existing fields ...
    by_channel: by_channel_for(dimension_value)  # NEW
  }
end

def by_channel_for(dimension_value)
  @by_channel_breakdown ||= by_channel_breakdown
  @by_channel_breakdown[dimension_value] || []
end
```

#### 2. Frontend Changes

**File**: `app/javascript/controllers/chart_controller.js`

Add a new chart type or modify `renderBarChart`:

```javascript
// In data-chart-type-value, support "stacked-bar" for this chart
// Or detect when by_channel data is present

renderConversionsByChart() {
  const data = this.parseData()
  if (!Array.isArray(data)) return

  const categories = data.map(d => d.channel) // conversion name/type

  // Get all unique channels across all conversion types
  const allChannels = [...new Set(
    data.flatMap(d => (d.by_channel || []).map(c => c.channel))
  )]

  // Build series per channel
  const series = allChannels.map(channel => ({
    name: this.formatChannelName(channel),
    color: CHANNEL_COLORS[channel] || CHANNEL_COLORS.other,
    data: data.map(d => {
      const channelData = (d.by_channel || []).find(c => c.channel === channel)
      return channelData ? channelData.credits : 0
    })
  }))

  this.chart = Highcharts.chart(this.chartElement, {
    chart: { type: "bar" },
    title: { text: null },
    xAxis: { categories },
    yAxis: { title: { text: "Conversions" }, stackLabels: { enabled: true } },
    legend: { enabled: true },
    plotOptions: { series: { stacking: "normal" } },
    series: series,
    credits: { enabled: false }
  })
}
```

#### 3. View Changes

**File**: `app/views/dashboard/conversions/_by_conversion_name_chart.html.erb`

Update the chart type:

```erb
<div id="conversion-name-chart"
  data-controller="chart"
  data-chart-type-value="stacked-bar"  <%# Changed from "bar" %>
  data-chart-metric-value="<%= chart_metric %>"
  data-chart-data-value="<%= by_conversion_name.to_json %>"
  class="h-64">
</div>
```

### Color Palette Reference

Use existing `CHANNEL_COLORS` from `chart_controller.js`:

| Channel | Color | Hex |
|---------|-------|-----|
| paid_search | Indigo | #6366F1 |
| organic_search | Emerald | #10B981 |
| paid_social | Amber | #F59E0B |
| organic_social | Lime | #84CC16 |
| email | Pink | #EC4899 |
| display | Violet | #8B5CF6 |
| affiliate | Teal | #14B8A6 |
| referral | Orange | #F97316 |
| video | Red | #EF4444 |
| direct | Gray | #6B7280 |
| other | Gray-400 | #9CA3AF |

### Tooltip Format

When hovering on a stacked bar segment:
```
Estimate Accepted
● Paid Search: 123.1 (24.5%)
● Direct: 149.4 (29.7%)
● Referral: 128.6 (25.6%)
─────────
Total: 503.1
```

---

## Implementation Checklist

### Bug Fixes (Priority: High)

- [x] Fix `visits_per_conversion` to use `journey_session_ids` array length
  - `app/services/dashboard/queries/totals_query.rb` - Added `journey_visits_per_conversion` method
  - `app/services/dashboard/queries/journey_metrics_by_channel.rb` - Updated `visits_per_conversion`
  - `app/services/dashboard/queries/by_conversion_name_query.rb` - Updated `visits_per_conversion`
- [x] Document `avg_days_to_convert` null issue (data pipeline issue, not query bug)
- [x] Add decimal precision (1 place) to number formatter
  - `app/helpers/dashboard_helper.rb` - Float values rounded to 1 decimal place
- [x] Write regression tests for all bugs
  - `test/services/dashboard/queries/totals_query_test.rb` - 3 new tests for journey-based visits
  - `test/helpers/dashboard_helper_test.rb` - 2 new tests for float precision

### Feature: Stacked Chart (Priority: Medium)

- [x] Add `by_channel` breakdown to `ByConversionNameQuery`
  - `app/services/dashboard/queries/by_conversion_name_query.rb` - Added `channel_breakdown` method
- [x] Add `renderConversionsByChannelChart` to chart_controller.js
  - `app/javascript/controllers/chart_controller.js` - New stacked bar renderer with channel colors
- [x] Update `_by_conversion_name_chart.html.erb` to use stacked-bar chart type
- [x] Write tests for new query method
  - `test/services/dashboard/queries/by_conversion_name_query_test.rb` - 2 new tests for by_channel
- [x] Tooltip shows channel breakdown with totals

---

## Testing Recommendations

### Unit Tests

```ruby
# test/services/dashboard/queries/totals_query_test.rb
test "avg_visits_to_convert is consistent across attribution models" do
  # Create conversion with 5 sessions in journey
  conversion = create_conversion(journey_session_ids: [s1, s2, s3, s4, s5].map(&:id))

  # Create credits for different models
  create_credit(conversion, first_touch_model, session: s1)
  create_credit(conversion, linear_model, session: s1)
  create_credit(conversion, linear_model, session: s2)
  # ... etc

  # Query with First Touch
  ft_result = query_with_model(first_touch_model)

  # Query with Linear
  linear_result = query_with_model(linear_model)

  # Both should report 5 visits (journey length), not credit count
  assert_equal 5, ft_result[:avg_visits_to_convert]
  assert_equal 5, linear_result[:avg_visits_to_convert]
end
```

### Integration Tests

Verify the dashboard renders correct values in both single-model and comparison modes.

---

## Files Modified

| File | Changes |
|------|---------|
| `app/services/dashboard/queries/totals_query.rb` | Fix visits calculation |
| `app/services/dashboard/queries/journey_metrics_by_channel.rb` | Fix visits calculation |
| `app/services/dashboard/queries/by_conversion_name_query.rb` | Fix visits + add channel breakdown |
| `app/helpers/dashboard_helper.rb` | Add precision to number formatter |
| `app/javascript/controllers/chart_controller.js` | Add stacked bar for conversions chart |
| `app/views/dashboard/conversions/_by_conversion_name_chart.html.erb` | Use stacked chart |
