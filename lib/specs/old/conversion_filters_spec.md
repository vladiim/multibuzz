# Conversion Filters & Breakdown Feature Spec

**Status**: ✅ Complete
**Created**: 2025-12-08
**Completed**: 2025-12-09

---

## Overview

Add a "Conversions by Name" chart to the conversion dashboard with:
1. Dimension/breakdown selector (default: Conversion Name, plus dynamic properties)
2. PostHog-style filter bar in the existing filters panel
3. Background job for property key discovery (not queried on every load)

---

## Implementation Checklist

### Phase 1: Database & Models ✅
- [x] Migration: Create `conversion_property_keys` table
- [x] Model: `ConversionPropertyKey` with concerns
- [x] Update `Account::Relationships` with has_many association

### Phase 2: Property Discovery System ✅
- [x] Service: `Conversions::PropertyKeyDiscoveryService`
- [x] Job: `Conversions::PropertyKeyDiscoveryJob`
- [x] Callback: Trigger discovery on conversion creation

### Phase 3: Query & Filter Infrastructure ✅
- [x] Query: `Dashboard::Queries::ByConversionNameQuery`
- [x] Scope: `Dashboard::Scopes::FilteredCreditsScope`
- [x] Update `Dashboard::ConversionsDataService`

### Phase 4: Controller Layer ✅
- [x] Update `Dashboard::BaseController` filter parsing
- [x] Controller: `Dashboard::ConversionFiltersController`
- [x] Routes for conversion_filters endpoints

### Phase 5: Frontend Components ✅
- [x] Stimulus: `conversion_filter_controller.js`
- [x] Partial: `_conversion_filters.html.erb`
- [x] Partial: `_filter_row.html.erb`
- [x] Partial: `_by_conversion_name_chart.html.erb`
- [x] Update existing views to include partials

### Phase 6: Polish & Testing ✅
- [x] Test all new components
- [x] Manual testing of filter bar interactions
- [x] Performance validation

---

## Database Schema

### Table: `conversion_property_keys` ✅

```ruby
create_table :conversion_property_keys do |t|
  t.references :account, null: false, foreign_key: true
  t.string :property_key, null: false
  t.integer :occurrences, default: 0, null: false
  t.datetime :last_seen_at
  t.timestamps
end

add_index :conversion_property_keys, [:account_id, :property_key], unique: true
add_index :conversion_property_keys, [:account_id, :occurrences]
```

---

## API Endpoints ✅

### GET `/dashboard/conversion_filters/dimensions`

Returns available dimensions for breakdown/filter dropdowns.

**Response:**
```json
[
  { "key": "conversion_type", "label": "Conversion Name", "type": "column" },
  { "key": "funnel", "label": "Funnel", "type": "column" },
  { "key": "revenue", "label": "Revenue", "type": "numeric" },
  { "key": "product_id", "label": "Product Id", "type": "property" },
  { "key": "plan", "label": "Plan", "type": "property" }
]
```

### GET `/dashboard/conversion_filters/values`

Returns matching values for autocomplete.

**Parameters:**
- `field` (required): The field to get values for
- `query` (optional): Search query for filtering

**Response:**
```json
["signup", "purchase", "trial_start"]
```

---

## Filter Parameters ✅

### URL Structure

```
/dashboard?conversion_filters[0][field]=conversion_type
          &conversion_filters[0][operator]=equals
          &conversion_filters[0][values][]=signup
          &conversion_filters[0][values][]=purchase
          &conversion_filters[1][field]=revenue
          &conversion_filters[1][operator]=greater_than
          &conversion_filters[1][values][]=100
          &breakdown=conversion_type
```

### Supported Operators ✅

| Operator | Label | Applicable To |
|----------|-------|---------------|
| `equals` | = equals | All fields |
| `not_equals` | ≠ not equals | String fields |
| `contains` | ~ contains | String fields |
| `greater_than` | > greater than | Numeric fields |
| `less_than` | < less than | Numeric fields |

---

## Data Flow ✅

```
1. User applies filter in UI
   ↓
2. Form submits with conversion_filters[] params
   ↓
3. BaseController parses conversion_filters_param
   ↓
4. ConversionsDataService receives filter_params
   ↓
5. FilteredCreditsScope applies filters to AR relation
   ↓
6. ByConversionNameQuery groups by selected dimension
   ↓
7. Results cached and rendered to chart
```

---

## Files Created ✅

| File | Purpose |
|------|---------|
| `db/migrate/*_create_conversion_property_keys.rb` | Migration |
| `app/models/conversion_property_key.rb` | Model |
| `app/models/concerns/conversion_property_key/validations.rb` | Validations |
| `app/models/concerns/conversion_property_key/scopes.rb` | Scopes |
| `app/services/conversions/property_key_discovery_service.rb` | Discovery service |
| `app/jobs/conversions/property_key_discovery_job.rb` | Background job |
| `app/services/dashboard/queries/by_conversion_name_query.rb` | Query object |
| `app/services/dashboard/scopes/filtered_credits_scope.rb` | Filter scope |
| `app/services/dashboard/scopes/operators/*.rb` | Filter operators |
| `app/controllers/dashboard/conversion_filters_controller.rb` | AJAX endpoints |
| `app/javascript/controllers/conversion_filter_controller.js` | Stimulus controller |
| `app/views/dashboard/conversions/_conversion_filters.html.erb` | Filter bar |
| `app/views/dashboard/conversions/_filter_row.html.erb` | Filter row template |
| `app/views/dashboard/conversions/_by_conversion_name_chart.html.erb` | Chart partial |

## Files Modified ✅

| File | Changes |
|------|---------|
| `app/models/concerns/account/relationships.rb` | Add has_many :conversion_property_keys |
| `app/models/concerns/conversion/callbacks.rb` | Add after_create callback |
| `app/controllers/dashboard/base_controller.rb` | Add filter param parsing |
| `app/services/dashboard/conversions_data_service.rb` | Add by_conversion_name query |
| `app/views/dashboard/filters/show.html.erb` | Include conversion_filters partial |
| `app/views/dashboard/conversions/_full_dashboard.html.erb` | Include chart partial |
| `config/routes.rb` | Add conversion_filters routes |

---

## Test Coverage ✅

### Controller Tests
- `Dashboard::ConversionFiltersController#dimensions`
- `Dashboard::ConversionFiltersController#values`
- Integration tests for filter application

### Service Tests
- `PropertyKeyDiscoveryService` discovers keys
- `ConversionDimensionsService` returns dimensions
- `ConversionValuesService` returns values

### Query Tests
- `ByConversionNameQuery` grouping behavior

### Scope Tests
- `FilteredCreditsScope` filter application
- All operator tests (equals, not_equals, contains, greater_than, less_than)

### Model Tests
- `ConversionPropertyKey` validations and scopes

---

## Bug Fixes Applied ✅

### Flat Properties Structure (2025-12-09)
- Fixed property storage from nested `{ "properties" => { "location" => "Sydney" } }` to flat `{ "location" => "Sydney" }`
- Updated `Conversions::TrackingService` to flatten properties on ingestion
- Created migration to flatten existing data
- Updated all queries to use flat property path

### Filter Preservation (2025-12-09)
- Fixed `hidden_filter_params` helper to properly serialize arrays of hashes
- Filters now preserved when changing breakdown dimension

### Malformed Params Handling (2025-12-09)
- Fixed `raw_filters` method to handle array of strings gracefully
- Added defensive checks for various param formats

---

## Performance Considerations ✅

1. **Property key discovery**: Background job, not on every dashboard load
2. **Caching**: Results cached with filter params in cache key
3. **Query limits**: Top 10 values in breakdown, top 20 in autocomplete
4. **JSONB indexes**: GIN index on properties column
