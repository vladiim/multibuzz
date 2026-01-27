# Spec: CLV Dashboard Filter Application

## Problem Statement

The Customer LTV dashboard has filter controls in the UI (date range, channels, conversion filters), but these filters are **not being applied** to the CLV queries. The filters appear to work (form submits, URL params update) but the data returned is unfiltered.

### Root Cause

In `Dashboard::ClvDataService`:

1. **Date Range**: `acquisition_conversions` fetches ALL acquisition conversions regardless of date filter
2. **Channel Filter**: Channels are included in `cache_params` but never applied to queries
3. **Conversion Filters**: Not extracted or applied at all

### Standard Dashboard vs CLV Dashboard (Current State)

| Filter | Standard Dashboard | CLV Dashboard (Broken) |
|--------|-------------------|------------------------|
| Date Range | ✅ Applied via `CreditsScope` | ❌ Ignored in `acquisition_conversions` |
| Channels | ✅ Applied via `CreditsScope` | ❌ In cache_params only |
| Conversion Filters | ✅ Applied via `FilteredCreditsScope` | ❌ Not implemented |
| Attribution Model | ✅ Applied | ✅ Applied |
| Test Mode | ✅ Applied | ✅ Applied |

---

## Solution Design

### Filter Application Strategy for CLV

CLV mode filters work differently from standard mode because we're filtering **acquisition cohorts**, not individual transactions.

| Filter | Standard Mode Meaning | CLV Mode Meaning |
|--------|----------------------|------------------|
| **Date Range** | Conversions that occurred in range | Customers **acquired** in range (cohort selection) |
| **Channels** | Credits from these channels | Customers acquired via these channels |
| **Conversion Filters** | Conversions matching filter criteria | Acquisition conversions matching criteria |

### Key Insight

In CLV mode, all filters apply to the **acquisition conversion**, not subsequent conversions. Once we identify the cohort of acquired customers, we show their full lifetime value (all subsequent conversions, regardless of when they occurred).

---

## Implementation

### 1. Apply Date Range to Acquisition Conversions

```ruby
# Before (broken):
def acquisition_conversions
  @acquisition_conversions ||= account.conversions
    .where(is_acquisition: true)
    .then { |scope| test_mode ? scope.test_data : scope.production }
end

# After (fixed):
def acquisition_conversions
  @acquisition_conversions ||= account.conversions
    .where(is_acquisition: true)
    .where(converted_at: date_range.to_range)
    .then { |scope| test_mode ? scope.test_data : scope.production }
end
```

### 2. Apply Channel Filter to Acquisition Conversions

Channel filtering in CLV mode means: "Show customers whose **acquisition channel** matches the filter."

This requires joining through attribution_credits to filter by the acquisition conversion's attributed channel:

```ruby
def acquisition_conversions
  @acquisition_conversions ||= base_acquisition_scope
    .then { |scope| apply_channel_filter(scope) }
    .then { |scope| apply_conversion_filters(scope) }
end

def base_acquisition_scope
  account.conversions
    .where(is_acquisition: true)
    .where(converted_at: date_range.to_range)
    .then { |scope| test_mode ? scope.test_data : scope.production }
end

def apply_channel_filter(scope)
  return scope if channels == Channels::ALL

  # Filter by acquisition channel from attribution credits
  conversion_ids_by_channel = AttributionCredit
    .where(attribution_model: attribution_model)
    .where(channel: channels)
    .pluck(:conversion_id)

  scope.where(id: conversion_ids_by_channel)
end
```

### 3. Apply Conversion Filters to Acquisition Conversions

Conversion filters (e.g., `conversion_type = "signup"`) should filter which acquisition conversions are included in the cohort.

```ruby
def apply_conversion_filters(scope)
  return scope unless conversion_filters.present?

  conversion_filters.reduce(scope) do |s, filter|
    Scopes::Operators.apply(s, filter)
  end
end

def conversion_filters
  @conversion_filters ||= filter_params[:conversion_filters] || []
end
```

### 4. Update Cache Params

Ensure cache key includes all filter components:

```ruby
def cache_params
  {
    model_id: attribution_model&.id,
    date_range: filter_params[:date_range],
    channels: channels.sort,
    conversion_filters: conversion_filters,  # Add this
    test_mode: test_mode
  }
end
```

---

## Test Cases

### Controller Tests

1. **Date range filter applies to CLV cohort selection**
   - Create acquisitions at 40 days ago and 10 days ago
   - Request with `date_range=30d`
   - Assert only the 10-day-ago customer appears

2. **Channel filter applies to acquisition channel**
   - Create acquisitions: one via Organic, one via Paid Search
   - Request with `channels=organic_search`
   - Assert only organic customer appears

3. **Conversion filters apply to acquisition conversions**
   - Create acquisitions: one signup, one trial_start
   - Request with `conversion_filters[0][field]=conversion_type&conversion_filters[0][operator]=eq&conversion_filters[0][values][]=signup`
   - Assert only signup customer appears

4. **Multiple filters combine correctly**
   - Create various acquisitions
   - Apply date + channel + conversion filter
   - Assert intersection of all filters

### Service Tests

1. **Date range filters acquisition_conversions**
2. **Channel filter excludes non-matching acquisition channels**
3. **Conversion filters apply to acquisition scope**
4. **Cache key changes when filters change**
5. **All downstream queries receive filtered cohort**

### Query Tests

1. **ClvTotalsQuery receives filtered identity_ids**
2. **ClvByChannelQuery receives filtered acquisition_conversions**
3. **SmilingCurveQuery receives filtered acquisition_conversions**
4. **CohortAnalysisQuery receives filtered acquisition_conversions**

---

## Acceptance Criteria

- [x] Date range filter limits CLV data to customers acquired in that range
- [x] Channel filter shows CLV for customers acquired via selected channels
- [x] Conversion filters narrow the acquisition cohort
- [x] All CLV metrics (totals, by_channel, smiling_curve, cohort_analysis) respect filters
- [x] Cache invalidates when filters change
- [x] No breaking changes to existing CLV functionality

---

## Files Modified

1. `app/services/dashboard/scopes/filtered_acquisitions_scope.rb` - **NEW** - Scope class for filtering acquisitions
2. `app/services/dashboard/scopes/operators/base.rb` - Added `table_name` param for direct queries
3. `app/services/dashboard/scopes/operators/equals.rb` - Use `column_hash` helper
4. `app/services/dashboard/scopes/operators/not_equals.rb` - Use `column_hash` helper
5. `app/services/dashboard/scopes/operators/contains.rb` - Use `column_path` helper
6. `app/services/dashboard/scopes/operators/greater_than.rb` - Use `column_path` helper
7. `app/services/dashboard/scopes/operators/less_than.rb` - Use `column_path` helper
8. `app/services/dashboard/clv_data_service.rb` - Delegate to FilteredAcquisitionsScope
9. `test/services/dashboard/clv_data_service_test.rb` - Added filter tests
10. `test/controllers/dashboard/conversions_controller_test.rb` - Added CLV filter tests
11. `test/controllers/dashboard/clv_mode_controller_test.rb` - Fixed test data and access patterns

---

## Implementation Notes

### Approach: Reuse Existing Operators

Rather than duplicating filter logic, we extended the existing `Dashboard::Scopes::Operators::*` classes to support both:
1. **Joined scopes** (default): `conversions.field` prefix for attribution_credits joined with conversions
2. **Direct queries**: No prefix for querying conversions table directly

This was achieved by adding a `table_name` parameter to `Operators::Base`:
- `table_name: "conversions"` (default) - for joined scopes
- `table_name: nil` - for direct conversion queries

### Architecture

```
ClvDataService
  └── FilteredAcquisitionsScope (NEW)
        ├── apply_date_range (direct filter)
        ├── apply_channels (via attribution_credits lookup)
        └── apply_conversion_filters
              └── FilterApplicator
                    └── Operators::* (with table_name: nil)
```

### Key Insights

1. **Date range = cohort selection**: In CLV mode, date range filters the acquisition cohort, not the transactions. Customers acquired in the date range show their FULL lifetime value.

2. **Channel filter via attribution_credits**: Channel filtering requires looking up which acquisition conversions have attribution credits in the selected channels.

3. **Operator reuse**: By parameterizing the table name in operators, we avoid code duplication between `FilteredCreditsScope` and `FilteredAcquisitionsScope`.

---

## Implementation Checklist

- [x] Write failing controller tests for CLV filters
- [x] Write failing unit tests for ClvDataService filters
- [x] Implement date_range filter in acquisition_conversions
- [x] Implement channel filter for acquisition channel
- [x] Implement conversion_filters for acquisition conversions
- [x] Update cache_params to include conversion_filters
- [x] Verify all tests pass (2189 tests, 0 failures)
- [x] Update this spec with implementation notes
