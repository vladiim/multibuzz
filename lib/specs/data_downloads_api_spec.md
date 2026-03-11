# Data Downloads API Specification

**Date:** 2026-03-12
**Priority:** P1
**Status:** Draft
**Branch:** `feature/data-downloads-api`

---

## Summary

Expose dashboard export data via authenticated API endpoints so customers can programmatically pull their attribution and funnel data into BI tools, data warehouses, and custom dashboards. Uses the existing API key authentication — no new auth mechanism needed.

---

## Problem

Customers can only download their data as CSV files from the dashboard UI. This requires a logged-in browser session and manual clicks. Teams that need automated data pipelines, scheduled syncs, or programmatic access have no option. The dashboard already shows an "API Extract" waitlist button — this spec delivers that feature.

---

## Current State

### CSV Exports (Dashboard-Only)

Two export services generate CSV strings served via `send_file`:

| Service | Data | Source |
|---------|------|--------|
| `Dashboard::CsvExportService` | One row per `AttributionCredit` with denormalized conversion + journey data | `app/services/dashboard/csv_export_service.rb` |
| `Dashboard::FunnelCsvExportService` | One row per raw session/event/conversion record | `app/services/dashboard/funnel_csv_export_service.rb` |

Both run as background jobs (`Dashboard::ExportJob`) and broadcast download links via Turbo Stream.

### API Authentication (Existing)

`Api::V1::BaseController` authenticates via `Bearer sk_{env}_{key}` header. The `ApiKeys::AuthenticationService` looks up the key by SHA256 digest, validates it's not revoked, checks account status, and sets `current_account` + `current_api_key`.

Source: `app/controllers/api/v1/base_controller.rb`, `app/services/api_keys/authentication_service.rb`

### Data Flow (Current)

```
Browser → Dashboard::ExportsController → ExportJob (background)
  → CsvExportService / FunnelCsvExportService
    → Scopes::FilteredCreditsScope / SessionsScope / EventsScope / ConversionsScope
      → CSV string → tmp/exports/ → send_file download
```

---

## Proposed Solution

### Endpoints

Two new JSON API endpoints that mirror the existing CSV exports:

```
GET /api/v1/data/conversions    → Attribution credit records
GET /api/v1/data/funnel         → Raw session/event/conversion records
```

### Why JSON (Not CSV)

| Consideration | JSON | CSV |
|---------------|------|-----|
| API convention | Standard — every existing endpoint returns JSON | Unusual for REST APIs |
| Typing | Numbers stay numbers, nulls stay nulls, nested objects preserved | Everything becomes strings |
| Pagination metadata | Natural — `meta` object alongside `data` array | Requires custom headers or separate response |
| Error responses | Consistent with existing API error format `{ error: "..." }` | Would need format switching on error |
| Client ergonomics | Parse once, use directly | Parse then cast types |
| Existing pattern | Matches `Api::V1::EventsController`, `SessionsController`, etc. | No existing API endpoint returns CSV |

CSV remains available via the dashboard for spreadsheet users. The API serves developers.

### Why Existing API Keys (Not New Auth)

The existing `ApiKey` model already:
- `belongs_to :account` — natural account scoping
- Distinguishes `test` vs `live` environments — data exports should respect this
- Has revocation, usage tracking, and audit logging built in
- Is authenticated by `Api::V1::BaseController` which all API endpoints inherit

Adding a separate auth mechanism would create confusion and maintenance burden. The API key already represents "this account's programmatic access" — data downloads are just another form of that access.

### Data Flow (Proposed)

```
API Client → GET /api/v1/data/conversions?start_date=...&page=1
  → Api::V1::DataController#conversions
    → authenticate_api_key (existing BaseController)
    → Data::ConversionsQueryService.new(account, params).call
      → Scopes::FilteredCreditsScope (reuse existing)
      → Paginate, serialize to hashes
    → render json: { data: [...], meta: { ... } }
```

### Response Format

**Conversions** (`GET /api/v1/data/conversions`):

```json
{
  "data": [
    {
      "date": "2026-03-01",
      "type": "conversion",
      "name": "purchase",
      "funnel": "sales",
      "attribution_model": "linear",
      "algorithm": "linear",
      "channel": "paid_search",
      "credit": 0.33,
      "revenue": 99.99,
      "revenue_credit": 33.33,
      "currency": "USD",
      "utm_source": "google",
      "utm_medium": "cpc",
      "utm_campaign": "brand",
      "is_acquisition": true,
      "properties": { "order_id": "ORD-123" },
      "journey_position": "first_touch",
      "touchpoint_index": 0,
      "journey_length": 3,
      "days_to_conversion": 5
    }
  ],
  "meta": {
    "total_count": 456,
    "page": 1,
    "per_page": 100,
    "total_pages": 5
  }
}
```

**Funnel** (`GET /api/v1/data/funnel`):

```json
{
  "data": [
    {
      "date": "2026-03-01",
      "type": "visit",
      "name": null,
      "funnel": null,
      "channel": "organic_search",
      "utm_source": "google",
      "utm_medium": "organic",
      "utm_campaign": null,
      "revenue": null,
      "currency": null,
      "is_acquisition": null,
      "properties": null
    },
    {
      "date": "2026-03-01",
      "type": "event",
      "name": "page_view",
      "funnel": "sales",
      "channel": "organic_search",
      "utm_source": "google",
      "utm_medium": "organic",
      "utm_campaign": null,
      "revenue": null,
      "currency": null,
      "is_acquisition": null,
      "properties": { "page": "/pricing" }
    }
  ],
  "meta": {
    "total_count": 1234,
    "page": 1,
    "per_page": 100,
    "total_pages": 13
  }
}
```

### Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `start_date` | `YYYY-MM-DD` | 30 days ago | Start of date range (inclusive) |
| `end_date` | `YYYY-MM-DD` | today | End of date range (inclusive) |
| `channels[]` | string array | all | Filter by channel(s) |
| `funnel` | string | all | Filter by funnel (funnel endpoint only) |
| `page` | integer | 1 | Page number |
| `per_page` | integer | 100 | Results per page (max 1000) |

Test mode is automatic: `sk_test_*` keys return test data, `sk_live_*` keys return live data. No `test_mode` param needed — the key environment determines it. This matches how ingestion endpoints work.

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Response format | JSON | API standard. CSV stays in dashboard for spreadsheet users. |
| Auth mechanism | Existing API keys | Already maps to account, has env distinction, revocation, logging. Zero new auth code. |
| Test/live data | Determined by API key environment | `sk_test_*` returns test data, `sk_live_*` returns live data. Consistent with ingestion endpoints. |
| Pagination | Offset-based (page/per_page) | Simpler than cursor-based. Sufficient for bounded date-range queries. |
| Max per_page | 1000 | Balances payload size with round-trip efficiency. |
| Default date range | 30 days | Prevents accidental full-table scans. Explicit range required for larger windows. |
| Endpoint namespace | `/api/v1/data/` | Distinct from ingestion endpoints. "data" is what customers want — their data. |
| Synchronous response | Yes | Unlike dashboard CSV (background job), API returns data inline. Pagination keeps response size bounded. |
| Column names | Match CSV exports | Same `type`/`name` convention. Customers switching from CSV get identical field names. |
| Service pattern | Query object (not ApplicationService) | Returns paginated data structure, not success/fail. |

---

## Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/controllers/api/v1/data_controller.rb` | API endpoint | **Create** |
| `app/services/data/conversions_query_service.rb` | Paginated conversions query | **Create** |
| `app/services/data/funnel_query_service.rb` | Paginated funnel query | **Create** |
| `config/routes.rb` | Routing | Add `data/conversions` and `data/funnel` routes |
| `test/controllers/api/v1/data_controller_test.rb` | Controller tests | **Create** |
| `test/services/data/conversions_query_service_test.rb` | Query service tests | **Create** |
| `test/services/data/funnel_query_service_test.rb` | Query service tests | **Create** |

Existing files reused (no changes):
- `app/services/scopes/filtered_credits_scope.rb`
- `app/services/scopes/sessions_scope.rb`
- `app/services/scopes/events_scope.rb`
- `app/services/scopes/conversions_scope.rb`
- `app/controllers/api/v1/base_controller.rb` (inherited)
- `app/services/api_keys/authentication_service.rb` (unchanged)

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path | Data exists in date range | JSON with `data` array + `meta` pagination |
| Empty result | No records match filters | `{ data: [], meta: { total_count: 0, page: 1, per_page: 100, total_pages: 0 } }` |
| No auth header | Missing `Authorization` | 401 `{ error: "Missing Authorization header" }` |
| Invalid key | Bad API key | 401 `{ error: "Invalid or expired API key" }` |
| Revoked key | Key revoked | 401 `{ error: "API key has been revoked" }` |
| Suspended account | Account not active | 401 `{ error: "Account suspended" }` |
| Test key | `sk_test_*` | Only test data returned |
| Live key | `sk_live_*` | Only live data returned |
| Invalid date format | `start_date=foo` | 400 `{ error: "Invalid start_date format. Use YYYY-MM-DD." }` |
| Date range too wide | `end_date - start_date > 365` | 400 `{ error: "Date range cannot exceed 365 days." }` |
| per_page too high | `per_page=5000` | Clamped to 1000, no error |
| per_page < 1 | `per_page=0` | Clamped to 1, no error |
| Page beyond range | `page=999` | `{ data: [], meta: { page: 999, ... } }` |
| Cross-account | Key from account A | Never returns account B data |
| Invalid channel | `channels[]=fake` | Ignored — filter applies only known channels |

---

## Implementation Tasks

### Phase 1: Query Services

- [ ] **1.1** Create `test/services/data/conversions_query_service_test.rb`
  - Returns paginated hash array matching CSV column names
  - Respects date range, channels, test_mode (via `is_test` flag)
  - Pagination: page, per_page, total_count, total_pages
  - Multi-account isolation
  - Empty result returns empty array with zero counts
- [ ] **1.2** Create `app/services/data/conversions_query_service.rb`
- [ ] **1.3** Create `test/services/data/funnel_query_service_test.rb`
  - Returns paginated hash array with visit/event/conversion rows
  - Respects date range, channels, funnel filter, test_mode
  - Pagination works across mixed record types
  - Multi-account isolation
- [ ] **1.4** Create `app/services/data/funnel_query_service.rb`
- [ ] **1.5** All query service tests green

### Phase 2: Controller + Routes

- [ ] **2.1** Add routes to `config/routes.rb`:
  ```ruby
  namespace :api do
    namespace :v1 do
      # existing routes...
      namespace :data do
        get "conversions", to: "data#conversions"
        get "funnel", to: "data#funnel"
      end
    end
  end
  ```
- [ ] **2.2** Create `test/controllers/api/v1/data_controller_test.rb`
  - Auth: 401 without header, with invalid key, with revoked key
  - Auth: 401 for suspended account
  - Success: 200 with correct JSON structure
  - Test key returns test data only
  - Live key returns live data only
  - Date params validation (bad format, range too wide)
  - Pagination params respected
  - Cross-account isolation
  - Both endpoints (conversions + funnel)
- [ ] **2.3** Create `app/controllers/api/v1/data_controller.rb`
- [ ] **2.4** All controller tests green

### Phase 3: Dashboard UI Update

- [ ] **3.1** Remove "API Extract" waitlist button from `app/views/dashboard/show.html.erb`
- [ ] **3.2** Replace with link to API docs or brief "Use API key" note (if API docs page exists for data endpoints)

### Phase 4: Full Suite + Ship

- [ ] **4.1** Full test suite passes (`bin/rails test`)
- [ ] **4.2** Manual QA: curl both endpoints with test key, verify JSON response
- [ ] **4.3** Manual QA: verify pagination, date filters, channel filters
- [ ] **4.4** Manual QA: verify test vs live key data isolation
- [ ] **4.5** Update spec, commit

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Conversions query | `test/services/data/conversions_query_service_test.rb` | Correct fields, pagination, filtering, account scoping |
| Funnel query | `test/services/data/funnel_query_service_test.rb` | Mixed record types, pagination, filtering, account scoping |

### Integration Tests

| Test | File | Verifies |
|------|------|----------|
| Auth enforcement | `test/controllers/api/v1/data_controller_test.rb` | All auth failure cases (401s) |
| Conversions endpoint | Same | 200 with correct JSON structure, field names, types |
| Funnel endpoint | Same | 200 with mixed record types, correct structure |
| Test/live isolation | Same | `sk_test_*` only sees test data |
| Cross-account | Same | Account A key never returns account B data |
| Param validation | Same | Bad dates → 400, pagination clamping |

### Manual QA

1. Generate test API key from dashboard
2. `curl -H "Authorization: Bearer sk_test_..." https://localhost:3000/api/v1/data/conversions`
3. Verify JSON response with `data` array and `meta` object
4. Test with `?start_date=2026-03-01&end_date=2026-03-12&per_page=10`
5. Test funnel endpoint similarly
6. Verify live key returns different (live) data
7. Verify revoked key returns 401

---

## Definition of Done

- [ ] `GET /api/v1/data/conversions` returns paginated JSON attribution credit data
- [ ] `GET /api/v1/data/funnel` returns paginated JSON funnel records
- [ ] Authenticated via existing API keys (no new auth)
- [ ] Test/live key environment determines data scope
- [ ] All query parameters work (date range, channels, funnel, pagination)
- [ ] Multi-account isolation verified
- [ ] All tests pass (unit + integration)
- [ ] "API Extract" waitlist removed from dashboard
- [ ] Spec updated and archived to `old/`

---

## Out of Scope

- CSV format via API (dashboard CSV exports remain for that use case)
- Webhooks / push-based data delivery
- Streaming / cursor-based pagination (offset is sufficient for bounded date ranges)
- Real-time data (API returns committed data, not in-flight)
- Custom field selection (all columns always returned)
- Rate limiting (disabled globally per `base_controller.rb:9-12` — revisit when billing tiers ship)
- API docs page for data endpoints (separate task)
- Async/background job API exports (pagination keeps responses fast)
