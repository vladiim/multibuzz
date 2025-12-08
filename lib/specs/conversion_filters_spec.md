# Conversion Filters & Breakdown Feature Spec

## Overview

Add a "Conversions by Name" chart to the conversion dashboard with:
1. Dimension/breakdown selector (default: Conversion Name, plus dynamic properties)
2. PostHog-style filter bar in the existing filters panel
3. Background job for property key discovery (not queried on every load)

---

## Implementation Checklist

### Phase 1: Database & Models
- [ ] Migration: Create `conversion_property_keys` table
- [ ] Model: `ConversionPropertyKey` with concerns
- [ ] Update `Account::Relationships` with has_many association

### Phase 2: Property Discovery System
- [ ] Service: `Conversions::PropertyKeyDiscoveryService`
- [ ] Job: `Conversions::PropertyKeyDiscoveryJob`
- [ ] Callback: Trigger discovery on conversion creation

### Phase 3: Query & Filter Infrastructure
- [ ] Query: `Dashboard::Queries::ByConversionNameQuery`
- [ ] Scope: `Dashboard::Scopes::FilteredCreditsScope`
- [ ] Update `Dashboard::ConversionsDataService`

### Phase 4: Controller Layer
- [ ] Update `Dashboard::BaseController` filter parsing
- [ ] Controller: `Dashboard::ConversionFiltersController`
- [ ] Routes for conversion_filters endpoints

### Phase 5: Frontend Components
- [ ] Stimulus: `conversion_filter_controller.js`
- [ ] Partial: `_conversion_filters.html.erb`
- [ ] Partial: `_filter_row.html.erb`
- [ ] Partial: `_by_conversion_name_chart.html.erb`
- [ ] Update existing views to include partials

### Phase 6: Polish & Testing
- [ ] Test all new components
- [ ] Manual testing of filter bar interactions
- [ ] Performance validation

---

## Database Schema

### New Table: `conversion_property_keys`

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

## API Endpoints

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

## Filter Parameters

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

### Supported Operators

| Operator | Label | Applicable To |
|----------|-------|---------------|
| `equals` | = equals | All fields |
| `not_equals` | ≠ not equals | String fields |
| `contains` | ~ contains | String fields |
| `greater_than` | > greater than | Numeric fields |
| `less_than` | < less than | Numeric fields |

---

## UI Components

### Filter Bar (PostHog-style)

```
┌─────────────────────────────────────────────────────────────────────┐
│ Filter conversions                                                   │
│                                                                      │
│ where  [Conversion Name ▾]  [= equals ▾]  [signup ×] [purchase ×]   │
│                                                                      │
│ [AND]  [Revenue ▾]          [> greater than ▾]  [100]               │
│                                                                      │
│ + Add filter                                                         │
└─────────────────────────────────────────────────────────────────────┘
```

### Breakdown Selector (in chart header)

```
┌─────────────────────────────────────────────────────────────────────┐
│ Conversions by Name                          [Conversion Name ▾]    │
│                                                                      │
│  █████████████████████████████████  signup (45%)                    │
│  ████████████████████              purchase (28%)                   │
│  ██████████████                    trial_start (18%)                │
│  ██████                            demo_request (9%)                │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow

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

## Files to Create

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
| `app/controllers/dashboard/conversion_filters_controller.rb` | AJAX endpoints |
| `app/javascript/controllers/conversion_filter_controller.js` | Stimulus controller |
| `app/views/dashboard/conversions/_conversion_filters.html.erb` | Filter bar |
| `app/views/dashboard/conversions/_filter_row.html.erb` | Filter row template |
| `app/views/dashboard/conversions/_by_conversion_name_chart.html.erb` | Chart partial |

## Files to Modify

| File | Changes |
|------|---------|
| `app/models/concerns/account/relationships.rb` | Add has_many :conversion_property_keys |
| `app/models/concerns/conversion/callbacks.rb` | Add after_create callback |
| `app/controllers/dashboard/base_controller.rb` | Add filter param parsing |
| `app/services/dashboard/conversions_data_service.rb` | Add by_conversion_name query |
| `app/views/dashboard/filters/show.html.erb` | Include conversion_filters partial |
| `app/views/dashboard/conversions/_full_dashboard.html.erb` | Include chart partial |
| `config/routes.rb` | Add conversion_filters routes |
| `config/recurring.yml` | Add scheduled job |

---

## Test Strategy (Outside-In TDD)

### 1. Controller Tests (Start Here)
- `Dashboard::ConversionFiltersController#dimensions`
- `Dashboard::ConversionFiltersController#values`
- Integration tests for filter application

### 2. Service Tests
- `PropertyKeyDiscoveryService` discovers keys
- `ConversionsDataService` includes by_conversion_name

### 3. Query Tests
- `ByConversionNameQuery` grouping behavior

### 4. Scope Tests
- `FilteredCreditsScope` filter application

### 5. Model Tests
- `ConversionPropertyKey` validations and scopes

---

## Performance Considerations

1. **Property key discovery**: Background job, not on every dashboard load
2. **Caching**: Results cached with filter params in cache key
3. **Query limits**: Top 10 values in breakdown, top 20 in autocomplete
4. **JSONB indexes**: Existing GIN index on properties column
