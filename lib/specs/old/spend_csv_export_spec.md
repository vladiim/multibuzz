# Spend CSV Export

**Date:** 2026-05-13
**Status:** Complete
**Branch:** `feat/conversion-feedback`

---

## Problem

The Spend dashboard at `/account/dashboard/spend` has no CSV export. Users who want to take their ad spend, attributed revenue, and ROAS into a spreadsheet or BI tool have to screenshot the page. Conversions and Funnel CSVs ship; spend does not.

This is also a hard prerequisite for the next spec (`dashboard_export_dropdown_spec.md`), which collapses the Export dropdown to a single tab-aware "Download CSV" line. That line can only support the Spend tab once a spend export exists.

---

## Solution

Add a third export type. Same pattern as `Dashboard::FunnelCsvExportService`: a service that streams CSV rows from one big SQL query against `ad_spend_records`, dispatched through `Dashboard::ExportJob`, persisted via the existing `Export` model and `tmp/exports/` flow.

One row per `(spend_date, channel, campaign, device, hour, metadata)` group — same grain as the dashboard's underlying `SpendIntelligence::Queries::ChannelMetricsQuery` and `BreakdownsQuery` results, so what users see in the dashboard is what they get in the CSV. No conversion / attribution columns in this export — that's already covered by the conversions CSV. Spend CSV is the platform-side numbers.

### Headers

```
spend_date, channel, platform, campaign_name, campaign_type, network_type,
device, spend_hour, spend, currency, impressions, clicks,
platform_conversions, platform_conversion_value, metadata
```

`platform` derived from `ad_platform_connections.platform` (joined). `spend` and `platform_conversion_value` rendered in major units (divide micros by 1,000,000) to match what the dashboard shows. `metadata` is the JSONB column rendered as a compact JSON string for spreadsheet round-trip.

### Files

| File | Purpose | Change |
|------|---------|--------|
| `app/models/export.rb` | `EXPORT_TYPES` constant | Add `"spend"` |
| `app/services/dashboard/spend_csv_export_service.rb` | New streaming CSV service | **Create** — mirror `FunnelCsvExportService` shape |
| `app/jobs/dashboard/export_job.rb` | Dispatch on `export_type` | Add `when "spend" then SpendCsvExportService.new(...)` branch + filename rule |
| `app/controllers/dashboard/exports_controller.rb` | `serialized_filter_params` | No change — spend reuses date_range + channels + test_mode already in the hash |
| `test/services/dashboard/spend_csv_export_service_test.rb` | Service tests | **Create** |
| `test/controllers/dashboard/exports_controller_test.rb` | Controller test | Add spend export-type test |
| `test/jobs/dashboard/export_job_test.rb` | Job test | Add spend dispatch test |

### Reused (no change)

- `SpendIntelligence::Scopes::SpendScope` filters (`production` / `test_data` / `for_date_range` / `for_channel`) — service builds raw SQL but applies the same filter shape
- `Export` model + `ExportJob` lifecycle (pending → processing → completed, Turbo broadcast, 1-hour expiry)

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Service style | Streaming SQL via `set_single_row_mode` | Matches `FunnelCsvExportService`. Spend tables get large fast (one row per campaign per hour per device). Don't load into memory. |
| Grain | One row per `ad_spend_records` row | Native grain. Aggregation happens downstream in the user's spreadsheet. Avoids surprise-aggregation bugs. |
| Filename | `mbuzz-spend-YYYY-MM-DD.csv` | Matches existing naming (`mbuzz-conversions-...`, `mbuzz-funnel-...`) |
| Spend in major units | Yes — divide micros by `AdSpendRecord::MICRO_UNIT` in SQL | Dashboard displays major units. CSV should match. |
| Metadata column | Compact JSON string of `metadata` JSONB | Lets users `JSON_VALUE(metadata, '$.location')` in Sheets / Excel. Empty `{}` for untagged rows. |
| Include `is_test` flag in output | No | `test_mode` filter already segregates. Mixing live + test rows in one file is a footgun. |
| Pagination | None — single file | Background job already runs async; users wait for the Turbo broadcast. |

## Acceptance Criteria

- [x] `Export::EXPORT_TYPES` includes `"spend"`; existing validation accepts it (sourced from `DashboardTabs::EXPORTABLE`)
- [x] `Dashboard::ExportsController#create` with `export_type=spend` creates an `Export` row and enqueues `ExportJob`
- [x] `Dashboard::ExportJob` dispatches `export_type=spend` to `Dashboard::SpendCsvExportService`
- [x] CSV file written to `tmp/exports/<prefix_id>.csv` with the headers above
- [x] Filename on download is `mbuzz-spend-YYYY-MM-DD.csv`
- [x] Service respects `date_range`, `channels`, `test_mode` from `filter_params`
- [x] Service scopes to `@account.ad_spend_records` — cross-account isolation test passes
- [x] Spend rendered in major units (e.g. `123.45`, not `123450000`)
- [x] `metadata` JSONB rendered as compact JSON string (`{"location":"Sydney"}`)
- [x] Empty-result case writes header row only, no data rows
- [x] Tests are integration-style — real DB, no mocks (per `feedback_no_mocks.md`)

## Deviations from draft

- Introduced `app/constants/dashboard_tabs.rb` (CONVERSIONS / FUNNEL / SPEND / EVENTS) as the single source of truth for these strings, since they're reused as tab identifiers in the dashboard view, export types in `Export`, and dispatch keys in `ExportJob`. Eliminated magic strings in the case/when dispatch and the controller default.
- Two test-infrastructure fixes were needed to keep CI stable once total test count crossed the parallel-worker threshold:
  - `Dashboard::ExportJob#export_dir` now scopes to a PID-keyed subdir under `tmp/exports/` in test env (parallel workers fork with the same `prefixed_ids` salt and were racing to write the same `tmp/exports/exp_<id>.csv` path).
  - `test/test_helper.rb` now eager-requires + includes `Turbo::Broadcastable::TestHelper`. The gem's `on_load(:action_cable)` callback fires too late for some forked workers, causing intermittent `undefined method 'assert_broadcasts'` errors on the pre-existing `test_broadcasts_download_link_on_completion`.

## Out of Scope

- Spend export filtered by metadata key/value — see `spend_dashboard_metadata_breakdown_spec.md` (different spec, different surface). Once that ships, metadata params flow through `filter_params` automatically and this export picks them up for free.
- ROAS / attributed revenue columns — covered by the conversions CSV. Joining spend ↔ conversions per row is a separate analytical product.
- Per-row attribution credit — not what a "spend" export is for.
- New filters (campaign, network type) — current dashboard doesn't expose them; if/when it does, this export auto-inherits via `filter_params`.

## Dependencies

None. Ready to start once approved.
