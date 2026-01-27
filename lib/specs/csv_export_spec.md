# CSV Data Export Specification

**Date:** 2026-01-29
**Priority:** P1
**Status:** Draft
**Branch:** `feature/csv-export`

---

## Summary

Customers need to export their attribution data for analysis in spreadsheets, BI tools, and internal reporting. The dashboard currently shows a "Coming Soon" export dropdown with waitlist buttons. This spec replaces the CSV waitlist with a working export that downloads a flat CSV of attribution credits -- the atomic unit of all dashboard metrics -- respecting whatever filters the user has active.

---

## Current State

### Export UI

The export dropdown in `app/views/dashboard/show.html.erb:57-83` uses `toggle_controller` to show two waitlist buttons: "CSV Export" and "API Extract". The Export button shows a "Soon" badge.

### Data Flow (Current)

```
User clicks Export → dropdown shows → waitlist buttons → no export happens
```

### Dashboard Query Architecture

All dashboard views aggregate from `AttributionCredit` via `Dashboard::Queries::*`:

```
Dashboard::BaseController (filter_params)
  → Dashboard::ConversionsDataService
    → Scopes::FilteredCreditsScope (applies all filters)
      → Queries::ByChannelQuery
      → Queries::TimeSeriesQuery
      → Queries::ByConversionNameQuery
      → Queries::TotalsQuery
      → Queries::TopCampaignsQuery
```

The scope layer (`Scopes::FilteredCreditsScope`) already handles: date_range, channels, attribution models, conversion_filters (dynamic field/operator/values), and test_mode. Source: `app/services/dashboard/scopes/filtered_credits_scope.rb`.

### Relevant Files

| File | Current Purpose | Will Change? |
|------|-----------------|--------------|
| `app/views/dashboard/show.html.erb` | Export dropdown with waitlist | Yes |
| `app/controllers/dashboard/base_controller.rb` | Provides `filter_params` | No |
| `app/services/dashboard/scopes/filtered_credits_scope.rb` | Applies all dashboard filters to credits | No (reused) |
| `config/routes.rb` | Dashboard routes | Yes (add 1 line) |

---

## Proposed Solution

Export a flat CSV where each row is one `AttributionCredit` with all dimensions denormalized from the related `Conversion` and `AttributionModel`. This is the right export format because every dashboard metric (by-channel, time-series, by-conversion-type) is an aggregation of these rows. Users can pivot by any dimension in their spreadsheet.

### Data Flow (Proposed)

```
User clicks Export → CSV Export button (form POST with current filters)
  → Dashboard::ExportsController#create
    → Dashboard::CsvExportService.new(account, filter_params).call
      → Scopes::FilteredCreditsScope (same filters as dashboard)
        → find_each with includes(:conversion, :attribution_model)
          → CSV.generate → send_data → browser downloads file
```

### CSV Columns

| Column | Source | Example |
|--------|--------|---------|
| `conversion_date` | `conversion.converted_at` as `YYYY-MM-DD` | `2026-01-15` |
| `conversion_type` | `conversion.conversion_type` | `purchase` |
| `funnel` | `conversion.funnel` | `sales` |
| `attribution_model` | `attribution_model.name` | `First Touch` |
| `algorithm` | `attribution_model.algorithm` | `first_touch` |
| `channel` | `attribution_credit.channel` | `paid_search` |
| `credit` | `attribution_credit.credit` (0-1) | `0.5` |
| `revenue` | `conversion.revenue` | `99.99` |
| `revenue_credit` | `attribution_credit.revenue_credit` | `49.99` |
| `currency` | `conversion.currency` | `USD` |
| `utm_source` | `attribution_credit.utm_source` | `google` |
| `utm_medium` | `attribution_credit.utm_medium` | `cpc` |
| `utm_campaign` | `attribution_credit.utm_campaign` | `summer_sale` |
| `is_acquisition` | `conversion.is_acquisition` | `true` |
| `conversion_properties` | `conversion.properties` as JSON string | `{"plan":"pro"}` |

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/services/dashboard/csv_export_service.rb` | Generate CSV from filtered credits | Create |
| `app/controllers/dashboard/exports_controller.rb` | Handle download request | Create |
| `test/services/dashboard/csv_export_service_test.rb` | Service tests | Create |
| `test/controllers/dashboard/exports_controller_test.rb` | Controller tests | Create |
| `config/routes.rb` | Add export route | Add 1 line |
| `app/views/dashboard/show.html.erb` | Replace export dropdown | Modify lines 57-83 |

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Row granularity | One row per `AttributionCredit` | Atomic unit -- all dashboard views aggregate from this. Preserves fractional credits for audit. |
| Sync vs async | Synchronous `send_data` | Most accounts have <100K credits. Simpler. Can add async later if needed. |
| HTTP method | POST (not GET) | Filter params can be complex (nested conversion_filters). Avoids URL length limits. |
| Service pattern | Plain class (not `ApplicationService`) | Returns CSV string, not success/fail. Documented exception per CLAUDE.md. |
| Turbo handling | `data: { turbo: false }` on form | Browser needs to handle file download natively. Turbo would intercept the response. |
| New Stimulus controller | None needed | Reuses existing `toggle_controller` for dropdown. Form submission handles download. |
| API Extract | Keep as waitlist | Not in scope for this iteration. |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path | Credits exist matching filters | CSV downloads with headers + data rows |
| Empty data | No credits match filters | CSV downloads with headers only (no rows) |
| No filters | User hasn't set any filters | Uses defaults (30d, all channels, default model) |
| Complex filters | Multiple conversion_filters active | All filters forwarded via hidden form fields |
| Test mode | `test_mode?` is true | Only test data exported |
| Not logged in | No session | Redirects to login (inherited from `BaseController`) |
| Large dataset | >50K credits | `find_each` streams in batches of 1000 |

---

## Implementation Tasks

### Phase 1: Service Layer

- [ ] **1.1** Create `test/services/dashboard/csv_export_service_test.rb`
  - [ ] Returns valid CSV string with correct headers
  - [ ] Rows contain denormalized credit + conversion + model data
  - [ ] Respects date_range filter
  - [ ] Respects channel filter
  - [ ] Respects attribution model filter
  - [ ] Respects conversion_filters
  - [ ] Respects test_mode
  - [ ] Multi-account isolation (account A cannot see account B data)
  - [ ] Empty data returns headers-only CSV
  - [ ] Handles nil values (revenue, UTM params, funnel, properties)
  - [ ] Conversion properties serialized as JSON string
- [ ] **1.2** Create `app/services/dashboard/csv_export_service.rb`
- [ ] **1.3** All service tests green

### Phase 2: Controller + Route

- [ ] **2.1** Add route inside `namespace :dashboard`: `resource :export, only: [:create], controller: "exports"`
- [ ] **2.2** Create `app/controllers/dashboard/exports_controller.rb`
- [ ] **2.3** Create `test/controllers/dashboard/exports_controller_test.rb`
  - [ ] Returns `text/csv` content type with `attachment` disposition
  - [ ] Filename includes current date (`multibuzz-export-YYYY-MM-DD.csv`)
  - [ ] Requires authentication (redirects if not logged in)
  - [ ] Returns 200 with empty data
- [ ] **2.4** All controller tests green

### Phase 3: View

- [ ] **3.1** Replace export dropdown in `app/views/dashboard/show.html.erb` (lines 57-83)
  - [ ] Remove "Soon" badge from Export button
  - [ ] CSV button is a `form_with` POST to `dashboard_export_path`
  - [ ] Current URL query params forwarded as hidden fields
  - [ ] `data: { turbo: false }` on form
  - [ ] API Extract remains as waitlist button with "coming soon" note
  - [ ] No new Stimulus controllers
- [ ] **3.2** Manual QA: set filters, click Export > CSV, verify file downloads with correct filtered data

### Phase 4: Polish + Ship

- [ ] **4.1** Full test suite passes (`bin/rails test`)
- [ ] **4.2** Test with test_mode toggle active
- [ ] **4.3** Test empty state (no conversions)
- [ ] **4.4** Update this spec: check off all tasks, note any deviations
- [ ] **4.5** Commit: `feat(export): add CSV export for attribution data`

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| CSV headers | `test/services/dashboard/csv_export_service_test.rb` | All 15 columns present in correct order |
| Data accuracy | Same file | Values match source records |
| Filter isolation | Same file | Each filter type excludes correct data |
| Account isolation | Same file | Cannot leak data across accounts |
| Edge cases | Same file | Nil values, empty properties, missing UTM |

### Integration Tests

| Test | File | Verifies |
|------|------|----------|
| Download flow | `test/controllers/dashboard/exports_controller_test.rb` | Content type, disposition, filename, auth |

### Manual QA

1. Log in to dashboard
2. Set date range to "Last 7 days"
3. Filter to "paid_search" channel only
4. Click Export > CSV Export
5. Open downloaded CSV
6. Verify: only rows within date range, only paid_search channel, all 15 columns present
7. Repeat with no filters -- verify all data included
8. Toggle test mode -- verify only test data exported

---

## Definition of Done

- [ ] All Phase 1-4 tasks completed
- [ ] Service tests pass
- [ ] Controller tests pass
- [ ] Full test suite passes (no regressions)
- [ ] Manual QA passed on dev
- [ ] "Coming Soon" badge removed from Export button
- [ ] CSV downloads correctly with all filters applied
- [ ] Spec updated with final state and moved to `old/`

---

## Out of Scope

- API Extract endpoint (stays as waitlist -- future spec)
- Async/background job export (not needed until accounts exceed ~100K credits)
- Export format options (Excel, JSON) -- CSV only for now
- Email delivery of exports
- Export history / saved exports
- Column selection UI (all columns always included)
- Scheduled/recurring exports

---

## Rollback Plan

| Scenario | Action |
|----------|--------|
| Export causes slow queries | Revert commit, re-add "Coming Soon" badge |
| Data leak across accounts | Revert immediately, investigate scope isolation |
