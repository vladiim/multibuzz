# Bug: Conversion Filters Not Showing Property Keys

## Problem

The conversion filter dropdown and breakdown chart are showing "Properties" as a single option instead of individual property keys (like "location", "plan", etc.).

### Current Behavior

1. **Filter dropdown**: Shows only "Properties" as an option, not individual keys
2. **Breakdown chart**: Shows "(not set)" with 348 conversions instead of breaking down by actual property values (e.g., "Port Melbourne", "Sydney", etc.)

### Expected Behavior

1. **Filter dropdown**: Should show individual property keys discovered from conversions:
   - conversion_type (built-in)
   - funnel (built-in)
   - location (from properties)
   - plan (from properties)
   - etc.

2. **Breakdown chart**: When "location" is selected, should show:
   - Port Melbourne: 50
   - Sydney: 100
   - Melbourne: 75
   - etc.

## Root Cause Analysis

### Issue 1: ConversionFiltersController#dimensions

The `dimensions` endpoint likely returns "Properties" as a category rather than individual discovered keys.

**File**: `app/controllers/dashboard/conversion_filters_controller.rb`

Check how dimensions are being returned - should be pulling from `conversion_property_keys` table.

### Issue 2: PropertyKeyDiscoveryService Not Populating Data

The discovery job may not have run, or may not be finding keys correctly.

**Files to check**:
- `app/services/conversions/property_key_discovery_service.rb`
- `app/jobs/conversions/property_key_discovery_job.rb`

**Action**: Run discovery job manually in production:
```ruby
Conversions::PropertyKeyDiscoveryJob.perform_now(Account.find_by(slug: "your-account"))
```

### Issue 3: View Partial Building Options Incorrectly

The filter row partial may be building the dimension options incorrectly.

**File**: `app/views/dashboard/conversion_filters/_filter_row.html.erb`

Check how the `<select>` options are being generated from the `dimensions` variable.

## Investigation Steps

1. **Check if property keys are discovered**:
```ruby
account = Account.find_by(slug: "multibuzz")
account.conversion_property_keys.pluck(:property_key)
# Expected: ["location", "plan", etc.]
# If empty: run discovery job
```

2. **Check dimensions endpoint response**:
```bash
curl -H "Cookie: ..." "https://mbuzz.co/dashboard/conversion_filters/dimensions"
# Should return: { dimensions: ["conversion_type", "funnel", "location", ...] }
```

3. **Check conversion properties structure**:
```ruby
account.conversions.limit(5).pluck(:properties)
# Verify structure is: { "properties" => { "location" => "..." } }
```

## Fix Checklist

- [ ] Verify `ConversionPropertyKey` records exist for the account
- [ ] Fix `ConversionFiltersController#dimensions` to return individual keys
- [ ] Update filter row partial to iterate over dimension keys
- [ ] Fix `ByConversionNameQuery` to correctly group by property values
- [ ] Run property discovery job in production

## Files to Modify

| File | Issue |
|------|-------|
| `app/controllers/dashboard/conversion_filters_controller.rb` | May be returning wrong format |
| `app/views/dashboard/conversion_filters/_filter_row.html.erb` | May be building options wrong |
| `app/views/dashboard/conversion_filters/_conversion_filters.html.erb` | Check dimensions passed to partial |
| `app/services/dashboard/queries/by_conversion_name_query.rb` | Verify grouping works |

## Testing

After fix, verify:
1. Filter dropdown shows: conversion_type, funnel, location, plan, etc.
2. Selecting "location" and value "Port Melbourne" filters correctly
3. Breakdown chart shows actual location values with correct counts
