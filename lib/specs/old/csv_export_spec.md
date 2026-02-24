# CSV Export: Unified Columns + Funnel Export

**Date:** 2026-02-25
**Priority:** P1
**Status:** Complete
**Branch:** `feature/session-bot-detection`

---

## Summary

The dashboard CSV export currently only covers attribution credits (conversions tab). Users need to export funnel data (visits, events, conversions) as raw records for analysis in spreadsheets and BI tools. While adding the funnel export, we'll also unify both exports around a shared `type`/`name` column convention — `type` identifies the stage (visit, event, conversion), `name` identifies the specific thing (event_type, conversion_type). This changes the existing conversion CSV headers, which will break existing tests.

---

## Current State

### Conversion CSV Export (Working)

`Dashboard::CsvExportService` exports one row per `AttributionCredit` with denormalized conversion data. Headers:

```
conversion_date, conversion_type, funnel, attribution_model, algorithm,
channel, credit, revenue, revenue_credit, currency,
utm_source, utm_medium, utm_campaign, is_acquisition, conversion_properties
```

Source: `app/services/dashboard/csv_export_service.rb`

The `ExportsController` ignores dashboard filters (always exports all models/channels, no conversion filters). Only date range and test mode are respected.

Source: `app/controllers/dashboard/exports_controller.rb:27-33`

### Funnel Dashboard (No Export)

`Dashboard::FunnelDataService` aggregates sessions, events, and conversions into stage counts with channel breakdowns. Uses three scopes:

- `Scopes::SessionsScope` — filters sessions by date_range, channels, test_mode
- `Scopes::EventsScope` — filters events by date_range, channels, funnel, test_mode
- `Scopes::ConversionsScope` — filters conversions by date_range, channels, test_mode

Source: `app/services/dashboard/funnel_data_service.rb`

### Export UI

The Export dropdown in `app/views/dashboard/show.html.erb:61-93` has one working button ("CSV Export") and one waitlist button ("API Extract"). The dropdown is visible on all tabs.

### Session UTM Data

Sessions store UTM in `initial_utm` JSONB with string keys: `"source"`, `"medium"`, `"campaign"`. Accessed via `session.initial_utm&.dig("source")` etc.

Source: `app/services/attribution/credit_enrichment.rb:63-67`

---

## Proposed Solution

### 1. Unified Column Convention

Both CSV exports share a `type`/`name` pattern:

| Column | Meaning | Examples |
|--------|---------|---------|
| `type` | Stage category | `visit`, `event`, `conversion` |
| `name` | Specific identifier within the stage | `page_view`, `add_to_cart`, `purchase`, `signup` |

For the conversion CSV, every row has `type` = `conversion` and `name` = the conversion_type value. For the funnel CSV, type varies per row.

### 2. Updated Conversion CSV Headers

```
date, type, name, funnel, attribution_model, algorithm,
channel, credit, revenue, revenue_credit, currency,
utm_source, utm_medium, utm_campaign, is_acquisition, properties
```

Changes from current:
- `conversion_date` → `date`
- `conversion_type` → `type` (always `conversion`) + `name` (the conversion_type value)
- `conversion_properties` → `properties`

### 3. New Funnel CSV Headers

```
date, type, name, funnel, channel,
utm_source, utm_medium, utm_campaign,
revenue, currency, is_acquisition, properties
```

One row per raw record (session, event, or conversion). No attribution columns (model, algorithm, credit, revenue_credit) — those belong to the conversion export.

| Row Type | `date` | `type` | `name` | `channel` | UTM source | `properties` |
|----------|--------|--------|--------|-----------|------------|-------------|
| Session | `started_at` | `visit` | `nil` | `session.channel` | `session.initial_utm` | `nil` |
| Event | `occurred_at` | `event` | `event_type` | join `session.channel` | join `session.initial_utm` | `event.properties` |
| Conversion | `converted_at` | `conversion` | `conversion_type` | join `session.channel` | join `session.initial_utm` | `conversion.properties` |

### Data Flow

```
Export dropdown → user picks "Conversions CSV" or "Funnel CSV"
  → POST /dashboard/export with export_type param
    → ExportsController reads export_type
      → "funnel" → FunnelCsvExportService.new(account, filter_params).call
      → default → CsvExportService.new(account, export_params).call
        → send_data → browser downloads file
```

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/constants/funnel_stages.rb` | Stage type constants | **Create** — `VISIT`, `EVENT`, `CONVERSION` |
| `app/services/dashboard/csv_export_service.rb` | Conversion CSV | Update headers: `date`, `type`, `name`, `properties`; use `FunnelStages::CONVERSION` |
| `app/services/dashboard/funnel_csv_export_service.rb` | Funnel CSV | **Create** |
| `app/controllers/dashboard/exports_controller.rb` | Download endpoint | Route to correct service based on `export_type` param |
| `app/views/dashboard/show.html.erb` | Export dropdown | Add "Funnel CSV" button alongside existing "CSV Export" (renamed "Conversions CSV") |
| `test/services/dashboard/csv_export_service_test.rb` | Conversion CSV tests | **Update** headers + column names |
| `test/services/dashboard/funnel_csv_export_service_test.rb` | Funnel CSV tests | **Create** |
| `test/controllers/dashboard/exports_controller_test.rb` | Controller tests | **Update** for routing + add funnel export tests |

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Unified `type`/`name` | Yes | Consistent mental model across exports. `type` = what stage, `name` = what specifically. |
| Funnel CSV granularity | One row per raw record (session/event/conversion) | Users want the raw data to pivot in their own tools. Aggregation is what the dashboard already does. |
| Funnel UTM source | Session's `initial_utm` for all row types | Session is the marketing touchpoint. Events/conversions inherit their session's UTM. |
| Controller routing | Single controller, `export_type` param | Keeps one route, one broadcast, shared auth. Avoids route proliferation. |
| Funnel CSV filters | Respects all dashboard filters (date_range, channels, funnel, test_mode) | Unlike conversion export which ignores filters, funnel export should match what the user sees. |
| Visits `name` column | `nil` | Visits don't have a sub-type. Landing page host is a different dimension. |
| Service pattern | Plain class (not `ApplicationService`) | Returns CSV string, not success/fail. Matches existing `CsvExportService`. |
| Filename convention | `mbuzz-conversions-YYYY-MM-DD.csv` / `mbuzz-funnel-YYYY-MM-DD.csv` | Clear which export type the file contains. Changes existing filename from `mbuzz-export-*`. |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path (conversions) | Credits exist | CSV with `type=conversion` rows, updated headers |
| Happy path (funnel) | Sessions + events + conversions exist | CSV with mixed `type` rows ordered by date |
| Empty (conversions) | No credits | Headers-only CSV |
| Empty (funnel) | No sessions/events/conversions | Headers-only CSV |
| Funnel filter active | `?funnel=sales` | Funnel CSV only includes events/conversions in that funnel; visits still included |
| Channel filter active | `?channels[]=paid_search` | Only records with matching channel |
| Test mode | `test_mode?` true | Only test data |
| No login | No session | Redirect to login |
| Large dataset | >50K records | `find_each` streams in batches |

---

## Implementation Tasks

### Phase 1: Update Conversion CSV Headers

- [x]**1.1** Update `CsvExportService::HEADERS` — rename `conversion_date` → `date`, replace `conversion_type` with `type` + `name`, rename `conversion_properties` → `properties`
- [x]**1.2** Update `CsvExportService#row_for` — add `"conversion"` for type, use conversion_type for name
- [x]**1.3** Update `test/services/dashboard/csv_export_service_test.rb` — fix all header references and assertions
- [x]**1.4** Update `test/controllers/dashboard/exports_controller_test.rb` — fix column name assertions
- [x]**1.5** All existing tests green with new headers

### Phase 2: Funnel CSV Export Service

- [x]**2.1** Create `test/services/dashboard/funnel_csv_export_service_test.rb`
  - [x]Returns valid CSV string with correct headers (12 columns)
  - [x]Visit rows: type=visit, name=nil, date=started_at, channel from session
  - [x]Event rows: type=event, name=event_type, date=occurred_at, channel from session join
  - [x]Conversion rows: type=conversion, name=conversion_type, date=converted_at, revenue/currency/is_acquisition populated
  - [x]UTM data sourced from session.initial_utm for all row types
  - [x]Rows ordered by date ascending
  - [x]Respects date_range filter
  - [x]Respects channels filter
  - [x]Respects funnel filter (events/conversions only — visits always included)
  - [x]Respects test_mode
  - [x]Multi-account isolation
  - [x]Empty data returns headers-only CSV
  - [x]Handles nil values (UTM, revenue, properties)
- [x]**2.2** Create `app/services/dashboard/funnel_csv_export_service.rb`
- [x]**2.3** All funnel service tests green

### Phase 3: Controller + Route + View

- [x]**3.1** Update `ExportsController#create` — route to `FunnelCsvExportService` when `params[:export_type] == "funnel"`
- [x]**3.2** Update filename to include export type (`mbuzz-conversions-*` / `mbuzz-funnel-*`)
- [x]**3.3** Update export dropdown in `dashboard/show.html.erb`:
  - Rename "CSV Export" → "Conversions CSV"
  - Add "Funnel CSV" button (same form pattern, hidden `export_type=funnel` field)
  - Both buttons include current query params as hidden fields
- [x]**3.4** Update `test/controllers/dashboard/exports_controller_test.rb` — add funnel export tests (content type, filename, empty state)
- [x]**3.5** All controller tests green

### Phase 4: Full Suite + Ship

- [x]**4.1** Full test suite passes (`bin/rails test`)
- [x]**4.2** Manual QA: export conversions CSV, verify new headers
- [x]**4.3** Manual QA: switch to funnel tab, export funnel CSV, verify visit/event/conversion rows with correct dimensions
- [x]**4.4** Manual QA: apply filters, verify funnel export respects them
- [x]**4.5** Update spec, commit

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Updated headers | `test/services/dashboard/csv_export_service_test.rb` | `date`, `type`, `name`, `properties` columns |
| Type column | Same file | Every row has `type=conversion` |
| Name column | Same file | `name` matches original `conversion_type` |
| Funnel headers | `test/services/dashboard/funnel_csv_export_service_test.rb` | 12 columns in correct order |
| Visit rows | Same file | type=visit, name=nil, session data |
| Event rows | Same file | type=event, name=event_type, joined session data |
| Conversion rows | Same file | type=conversion, name=conversion_type, revenue |
| UTM from session | Same file | All row types get UTM from session.initial_utm |
| Filter isolation | Same file | date_range, channels, funnel, test_mode |
| Account isolation | Same file | No cross-account data leakage |

### Integration Tests

| Test | File | Verifies |
|------|------|----------|
| Conversion download | `test/controllers/dashboard/exports_controller_test.rb` | Content type, disposition, updated filename |
| Funnel download | Same file | Content type, disposition, funnel filename |
| Export type routing | Same file | `export_type=funnel` routes to funnel service |

### Manual QA

1. Log in, go to dashboard
2. Click Export > Conversions CSV — verify file downloads with new headers (`date`, `type`, `name`, `properties`)
3. Verify every row has `type=conversion`, `name` matches conversion_type
4. Switch to Funnel tab, click Export > Funnel CSV
5. Open CSV — verify visit/event/conversion rows with correct `type`/`name`
6. Apply channel filter to paid_search only, export funnel — verify only paid_search rows
7. Select a funnel from dropdown, export — verify events/conversions filtered, visits still present
8. Toggle test mode — verify only test data exported

---

## Breaking Changes

Existing conversion CSV headers change. Affected tests:

| Test File | What Breaks |
|-----------|-------------|
| `test/services/dashboard/csv_export_service_test.rb` | Header assertions, `conversion_date`/`conversion_type`/`conversion_properties` column references |
| `test/controllers/dashboard/exports_controller_test.rb` | Filename assertion (`mbuzz-export-*` → `mbuzz-conversions-*`), column name assertions |

Both test files need updating in Phase 1 before any new code is written.

---

## Definition of Done

- [x] Conversion CSV uses `date`, `type`, `name`, `properties` headers
- [x] Funnel CSV exports visits, events, conversions as raw records
- [x] Both exports share the `type`/`name` convention
- [x] Export dropdown has two options: "Conversions CSV" and "Funnel CSV"
- [x] All tests pass (updated + new)
- [x] Spec updated and archived to `old/`

---

## Out of Scope

- API Extract endpoint (stays as waitlist)
- Async/background job export
- Column selection UI
- Export format options (Excel, JSON)
- Funnel export with attribution data (credits, models) — that's the conversion export
- Conversion filters on funnel export (funnel doesn't use `FilteredCreditsScope`)
- Visitor-level aggregation (e.g. "first visit date per visitor") — rows are raw records
