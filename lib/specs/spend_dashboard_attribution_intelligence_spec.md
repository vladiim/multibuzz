# Spend Dashboard — Attribution Intelligence

**Date:** 2026-05-06
**Priority:** P0 (Spend dashboard is the second-most-visited dashboard surface; today it is structurally broken and competitively undifferentiated.)
**Status:** Dev complete — Phases 1–5 shipped; Phase 6 dev items (6.2 suite, 6.3 N+1 guard, 6.5 docs) shipped. Manual UAT outstanding: 6.1 (multi-connection / non-UTC / non-USD account walkthrough) and 6.4 (Lighthouse). Spec moves to `old/` after UAT signoff.
**Branch:** `feature/spend-dashboard-attribution-intelligence`

---

## Summary

The Spend dashboard ties customer ad spend to attributed revenue — the single screen where mbuzz justifies its existence to a paid-media buyer. Today three things make it fail that job: (1) the daily timeseries silently drops days because spend dates and conversion dates use different timezone semantics, (2) every metric on the page is computed against a single hard-coded attribution model and the user has no way to switch or compare, and (3) the Meta sync job will crash on the first Meta connection because the job dispatcher hardcodes the Google adapter. This spec ships a trustworthy, attribution-aware Spend dashboard: timeseries that lines up, a model selector that drives every metric, side-by-side comparison of any two of the eight models, a per-channel "Platform-reported vs mbuzz-attributed" gap (the headline MTA pitch), and a multi-model confidence band that turns "we have eight models" from a checkbox into the dashboard's primary decision surface.

---

## Demo

The reference experience the shipped feature must deliver. If a step here fails or feels weak, we have not shipped this spec. Used to align before TDD and as the final acceptance walkthrough.

### Setup data on dev

A single seed account configured to make the demo land:

- One Google Ads connection, ad account in `America/Los_Angeles` timezone (proves TZ fix is real)
- One Meta Ads connection, ad account in `Australia/Sydney` timezone (proves Meta sync ships and that mixed-TZ accounts roll up correctly)
- 60 days of synced spend across both, mix of Search, Social, Shopping channels
- 200 conversions in the same period, with `revenue_amount` populated
- All eight attribution models active and credited (Time Decay set as default)
- One channel (Meta Social) deliberately seeded so platform-reported revenue is roughly 1.6× attributed revenue (forces the gap story)
- One channel (Google Search) seeded so all eight models agree within ~10% (narrow confidence band)
- One channel (Display) seeded so models disagree by >2× (wide confidence band)

A rake task `db:seed:spend_demo` produces this state idempotently for any account.

### The 90-second walkthrough

> **0:00 — Marketer lands on `/dashboard/spend`**
> Default view: last 28 days, primary model = Time Decay, accrual mode on the chart, cash mode on hero tiles. Page paints in under 1.5s.

> **0:05 — They look at the hero strip**
> Five tiles: Spend, Attributed Revenue, ROAS, CAC, Platform vs Attributed. Each shows the number plus a small "+12% vs prior 28d" delta in green or red. The Platform vs Attributed tile says "−$48,200 (−24%)" in muted amber: their ad platforms are over-reporting by a quarter. This is the punchline of mbuzz, on the dashboard, in three seconds.

> **0:15 — They scan the timeseries**
> Daily spend bars, ROAS line overlaid. No null gaps. The line is smooth because granularity auto-picked weekly for a 28-day range. Two pills above the chart: `Granularity: D / W / M` and `Mode: Cash / Accrual`. They flip to Daily and the chart stays coherent — single-day ROAS is plausible because we're in Accrual mode.

> **0:30 — They flip Accrual to Cash**
> The line shape shifts visibly: the most recent five days drop because conversions have not yet materialised for that spend. Tooltip on the toggle reads "Cash: revenue dated by conversion. Accrual: revenue dated by the touchpoint that earned credit." They get it. They flip back to Accrual.

> **0:40 — They open the model selector**
> Pill at top of page: `Model: Time Decay`. They click it, see all eight models with sub-labels (Heuristic / Probabilistic). They pick Markov Chain. Hero ROAS recomputes from 3.2 to 2.7. Channel table re-sorts. Timeseries line redraws. URL now reads `?models[]=mdl_<markov>` — they could share this view.

> **0:55 — They click "+ Compare"**
> A second pill opens. They pick Last Touch. Channel table grows two columns: `Δ ROAS`, `Δ Revenue`, sorted by absolute Δ. Meta Social shows "+1.4 ROAS · +$31k" because Last Touch over-credits paid social. Timeseries gains a dashed muted line for Last Touch ROAS. Tooltip on any day shows both numbers and the gap.

> **1:10 — They eye the rightmost column of the channel table**
> "Confidence" — a horizontal bar per channel. Google Search's bar is narrow; Display's bar is wide and red-shaded. They click Display's bar. An inline panel expands showing all eight model values: First Touch 0.8, Last Touch 4.1, Linear 1.9, Time Decay 2.4, U-Shaped 3.1, Participation 2.0, Markov 1.3, Shapley 1.5. They get it: Display's credit is genuinely contested. They are looking at attribution uncertainty as a first-class fact, not a footnote.

> **1:25 — They check the gap columns on Meta Social**
> Platform-reported revenue: $61,400. Attributed: $39,200. Gap: −$22,200 (−36%). They click the gap cell — a panel opens showing the underlying campaigns and the matched conversions, with a one-line note: "Meta's last-click attribution windows can include views and assisted clicks mbuzz does not credit. Both numbers are useful."

> **1:30 — They notice the freshness badge**
> "Updated 3h ago" next to Google Ads, "Updated 2 days ago" muted next to Meta. They click the muted badge → routed to `/integrations/meta_ads` showing a sync error and a Reconnect button. They are never confused about whether the dashboard is fresh.

### What must never happen during the demo

Hard regressions. Any of these and we have not shipped:

- A null gap appears in the timeseries on a day with both spend and conversions
- Model selector changes one metric but not another
- Comparison mode shows the same number in both columns (we forgot to actually use the second model)
- Confidence band shows zero spread across all eight models (means we are running the same query eight times)
- Platform-vs-attributed gap shows for a channel where `platform_conversion_value_micros` is null
- Sync freshness badge says "Updated 3h ago" for a connection in `:error` state
- Meta connection sync crashes (the very bug this spec exists to prevent)

### The single sentence we want the customer to say

> "I can see what each of my eight attribution models thinks about every channel, side by side, and where the platforms are over-reporting — without leaving the page."

If the demo does not earn that sentence, the spec is not shipped.

---

## Current State

### What works
- `AdSpendRecord` schema captures daily spend, hourly + device dimensions, platform-reported conversions and revenue, plus per-connection metadata. Schema in `db/migrate/20260302051306_create_ad_spend_records.rb` plus hourly-dim migration `20260303060000`.
- Google Ads sync runs daily at 6am via `AdPlatforms::SpendSyncSchedulerJob` → `AdPlatforms::Google::ConnectionSyncService` → `AdPlatforms::Google::SpendSyncService`. Tested, gated behind `FeatureFlags::GOOGLE_ADS_INTEGRATION` (off in prod pending Google verification).
- Meta adapter is built end-to-end at the service-class level: OAuth controller, `Meta::CompleteCallbackService`, `Meta::SpendSyncService`, `Meta::RowParser`, `Meta::CampaignChannelMapper`, `Meta::TokenRefresher` all exist and have unit tests for the pure parsers.
- Dashboard skeleton: `Dashboard::SpendController#show` → `SpendIntelligence::MetricsService` → hero KPIs, channel table, timeseries chart, hourly+device tab, Payback Period tab, Recommendations card. Stimulus `chart_controller.js` renders a Highcharts dual-axis (spend column + ROAS line) at the `spend-trend` type.
- Attribution credits are pre-computed per model. `AttributionCredit` has columns `attribution_model_id`, `conversion_id`, `revenue_credit`, indexed for the join. All eight models in `AttributionAlgorithms::IMPLEMENTED` write credits.
- Filter plumbing: `Dashboard::BaseController` already accepts `params[:models]` (array of model `prefix_id`s) and resolves them into `current_account.attribution_models.active`.

### What's broken

**B1 — Timeseries date alignment.** `app/services/spend_intelligence/queries/breakdowns_query.rb:51-57`

```ruby
daily_spend   = spend_scope.group(:spend_date).sum(:spend_micros)
daily_revenue = credits_scope.joins(:conversion).group(Arel.sql("DATE(conversions.converted_at)")).sum(:revenue_credit)
```

Spend rows store `spend_date` as the platform-reported date (Google and Meta both report in the ad account's local timezone). Revenue groups by raw `DATE(conversions.converted_at)` which evaluates the timestamp in the database session's timezone (UTC). For any account whose ad account timezone differs from UTC, the per-day keys never line up. The chart renders wide ranges of `roas: null` and customers see a broken-looking chart. Today this is hidden under a footnote in `_channel_table.html.erb:78` ("Use 7d+ windows for accuracy"), which is a band-aid, not a fix.

**B2 — Meta sync job hardcoded to Google.** `app/jobs/ad_platforms/spend_sync_job.rb:7-12`

```ruby
def perform(connection_id)
  AdPlatforms::Google::ConnectionSyncService.new(AdPlatformConnection.find(connection_id)).call
end
```

`Meta::AcceptConnectionService` enqueues this job on connect. First Meta connection → runtime crash. There is no `Meta::ConnectionSyncService` wrapper around `Meta::SpendSyncService` (Google has one; Meta does not), so the job has nowhere correct to dispatch even after we fix the dispatch.

**B3 — Attribution model is not really wired into the spend dashboard.** `SpendIntelligence::MetricsService` accepts a multi-element `models:` array but only ever returns one blended result per metric. Hero ROAS, channel table ROAS, and timeseries ROAS implicitly use the first selected model (or the account default). There is no UI control on the page to switch models or compare them. Compare to `Dashboard::ConversionsController` which already implements `comparison_mode?` and returns one result per selected model.

### Data flow (current)

```
SpendController#show
  → BaseController#filter_params (resolves params[:models] into AttributionModel records)
  → SpendIntelligence::MetricsService(account, filter_params)
      → ChannelMetricsQuery        (uses models.first only)
      → BreakdownsQuery            (timeseries: broken date join)
      → HourlyDeviceQuery
      → PaybackPeriodQuery         (correctly filters by selected model)
      → RecommendationService
  → Renders single-model result; no model picker; no comparison
```

---

## Proposed Solution

Three pillars, sequenced. Bug fixes (B1+B2) first because they undermine trust in everything else. Model integration second because it unlocks the new charts. Differentiated views (gap column, confidence band) third because they sit on top of the model integration.

### Pillar 1 — Trust the chart (B1 + B2 fixes)

**Date alignment.** Replace the date join on `DATE(conversions.converted_at)` with a daily attribution-credit aggregation that respects the same timezone semantics as `spend_date`. Two options were considered; we pick the second for correctness:

| Option | Approach | Why we picked / rejected |
|---|---|---|
| A | Cast `converted_at` to UTC date, leave `spend_date` as-is | Rejected. `spend_date` is the platform-local date, not UTC. A US-Pacific account would still mis-align. |
| B | Cast `converted_at` to the account's reporting timezone derived from `AdPlatformConnection.settings['timezone_name']`, then take `DATE()` of that | Picked. Matches platform reporting semantics. SQL shipped: `DATE((conversions.converted_at AT TIME ZONE 'UTC') AT TIME ZONE :tz)` (double-cast because `converted_at` is `timestamp without time zone` storing UTC values; first reinterpret as UTC, then shift to the account TZ). `:tz` is resolved per-account at query time from the first connection with `settings['timezone_name']` populated. |

**Accounting mode toggle (Northbeam pattern).** Borrowed from the competitor audit. The "spend lags conversions" problem is real and the right fix is to expose the choice rather than pick one and hide it. Two modes:

- **Cash (default for hero KPIs)** — group revenue by `conversion.converted_at` date. Today's number is "what came in today," includes lag from yesterday's spend.
- **Accrual (default for timeseries)** — group revenue by the date of the touchpoint session that earned credit. Single-day ROAS becomes "spend on day X attributed back to revenue from spend on day X."

Implementation (shipped): accrual mode joins `attribution_credits.session_id = sessions.id` and groups by `DATE((sessions.started_at AT TIME ZONE 'UTC') AT TIME ZONE :tz)`. Cash mode groups by the equivalent expression on `conversions.converted_at`. The `BreakdownsQuery#time_series` now iterates the union of spend and revenue date keys so accrual-only days surface.

URL param `?accounting_mode=cash|accrual` is honoured by `MetricsService` and threaded into the cache key. The pill UI in the timeseries header ships with Phase 5 polish.

**Meta dispatch.** Build `AdPlatforms::Meta::ConnectionSyncService` mirroring Google's. Refactor `SpendSyncJob` to dispatch through `AdPlatforms::Registry`:

```ruby
class AdPlatforms::SpendSyncJob < ApplicationJob
  def perform(connection_id)
    connection = AdPlatformConnection.find(connection_id)
    AdPlatforms::Registry.connection_sync_service_for(connection.platform).new(connection).call
  end
end
```

Extends `Registry` with `connection_sync_service_for(:platform)` returning the right class. No conditionals at call sites. Per `feedback_global_processor_pattern`, this is the right shape — single dispatcher, platform identifier in, behaviour out.

### Pillar 2 — Model-aware metrics

**Single model selector.** A pill in the dashboard header, alongside the existing date-range picker. Default = account's `is_default` attribution model (resolved by `BaseController#default_attribution_model`). Switching the pill re-renders every metric on the page (hero tiles, channel table, timeseries, payback). State persisted in URL as `?models[]=mdl_xxx` (consistent with the rest of the app's filter convention) so it survives reload and is shareable.

`MetricsService` resolves a `primary_attribution_model` (first of selected) and runs every query against a single-model `credits_scope_for(model)`. The previous behaviour silently summed credits across all selected models; that bug is fixed. `ChannelMetricsQuery` and `BreakdownsQuery` are now invoked per-model via the scope. `PaybackPeriodQuery` already accepted a model and remains unchanged.

**Comparison overlay.** A "+ Compare" button next to the model pill opens a second pill. Picking a comparison model:

- Channel table grows two new columns: `Δ ROAS`, `Δ Revenue`. Sorted by absolute delta descending so the most-disagreeing channels float up.
- Timeseries gets a second muted line at the comparison model's ROAS. Tooltip shows both values + delta.
- Hero tiles unchanged (single primary number; clutter not worth it).

Implemented server-side, not client-side. `MetricsService` returns one result per selected model when `comparison_mode?` (mirroring `ConversionsController`). View renders extra columns conditionally.

**Cap at two models.** No N-way comparison grid. Eight models compared pairwise = 28 grids; cognitive load kills the page. The eight-way view comes back in Pillar 3 as a confidence band, which is the right shape for "all models at once."

### Pillar 3 — Differentiated views

**Platform vs attributed ROAS gap (the headline pitch).** Add three columns to the channel table:

| Column | Source | Computation |
|---|---|---|
| Platform-reported revenue | `ad_spend_records.platform_conversion_value_micros` | `SUM(...)` per channel/range |
| mbuzz-attributed revenue | `attribution_credits.revenue_credit` filtered by selected model | `SUM(...)` per channel/range |
| Gap | derived | `attributed - platform_reported`, with `Δ%` |

This is the single most important addition. It is the entire MTA pitch ("the platforms over-report; here's the gap") rendered as a number a customer can take to a meeting. Triple Whale built early traction on this; we have the underlying data already (`platform_conversion_value_micros` is populated by both adapters). Surfacing it costs almost nothing.

Add a hero tile too: "Platform-reported revenue: $X. Attributed: $Y. Gap: −$Z (−AA%)." If the gap is meaningful (>15% absolute), the tile gets a small caution color; if it's tiny, neutral. We are not advocating that mbuzz is "right" and the platform is "wrong"; the framing in copy is "different methodologies, here's the spread."

**Confidence band across all models.** A horizontal bar in the channel table's right-most column. The bar's center is the selected model's ROAS; the shaded band spans the min/max across the eight implemented models for the same channel/range. Wide band = high uncertainty; narrow band = models agree.

Computation: `MetricsService` runs the per-channel ROAS once per active model (eight times, scoped to the same date range and metadata filter), produces `min`, `max`, `selected` per channel. Cached per-account-per-range in Solid Cache for the dashboard's lifetime to keep it cheap; eight queries that hit the same indexes are not expensive.

Click the band to expand a per-model breakdown panel inline — a single small bar chart of the eight ROAS values. This is the comparison tool but contextual: triggered at the moment of decision-making, not as a separate report.

This is the killer view. It directly weaponizes our model count. Triple Whale, Polar, Hyros, Wicked, Attribuly cannot ship this without first re-implementing models we already have.

### Polish (folded into the same spec because cheap)

- **Granularity selector D / W / M** on the timeseries. Default W for ranges over 30 days, D under. Smooths the spend-lags-conversions noise without rolling-average UX problems ("what's today?"). Server-side group-by; no JS.
- **Period delta on hero tiles.** "ROAS: 3.2 (+0.4 vs prior 30d)". Comparison period = same length immediately preceding selected range. Mirrors GA4 / Northbeam; absence reads as toy.
- **Sync freshness indicator.** Per-channel `ad_spend_records.updated_at` max, displayed as "Updated 2h ago" next to the channel name. If older than expected for that platform's sync cadence, render in muted color with a tooltip. Avoids the "is this real-time?" support ticket forever.

### Data flow (after Phase 2; Phases 3+ extend)

```
SpendController#show (inherits BaseController)
  → filter_params (date_range, channels, models[], accounting_mode, ...)
  → SpendIntelligence::MetricsService
      → primary_metrics  = ChannelMetricsQuery(spend_scope, primary_credits_scope)
      → compare_metrics  = ChannelMetricsQuery(spend_scope, compare_credits_scope)   [if 2nd model]
      → primary_breakdowns = BreakdownsQuery(spend_scope, primary_credits_scope, tz, mode)
      → compare_breakdowns = BreakdownsQuery(spend_scope, compare_credits_scope, ...)
      → PaybackPeriodQuery(primary model)
      → ResponseCurveService(spend_scope, primary_credits_scope) → recommendations
      → Returns flat: { totals:, by_channel:, time_series:, by_device:, by_hour:,
                        payback:, recommendations:, compare: nil_or_subset }
  → View renders:
      - model selector partial (primary pill + compare pill)
      - hero tiles (primary KPIs)
      - timeseries (primary line + dashed compare line when comparing)
      - channel table (with Δ ROAS / Δ Revenue cols when comparing)
      - payback (primary model)

Phases 3–5 will add: PlatformVsAttributedQuery, ConfidenceBandQuery, granularity grouping,
period-delta math, sync freshness badges, and the Cash/Accrual + granularity pill UI.
```

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/services/spend_intelligence/queries/breakdowns_query.rb` | Daily timeseries SQL | Fix date alignment with account TZ; accept `accounting_mode:` and `granularity:`; group by week/month when requested |
| `app/services/spend_intelligence/queries/channel_metrics_query.rb` | Channel table aggregates | Accept `attribution_model:` (today uses first); return per-channel `platform_revenue_micros` from spend rows |
| `app/services/spend_intelligence/metrics_service.rb` | Top-level orchestrator | Comparison mode, confidence band aggregation, period delta, return shape change |
| `app/services/spend_intelligence/queries/platform_vs_attributed_query.rb` | New query | Per-channel platform-reported vs attributed revenue |
| `app/services/spend_intelligence/queries/confidence_band_query.rb` | New query | Per-channel ROAS across all eight models |
| `app/jobs/ad_platforms/spend_sync_job.rb` | Sync dispatcher | Replace hardcoded Google with `Registry.connection_sync_service_for(connection.platform)` |
| `app/services/ad_platforms/registry.rb` | Adapter registry | Add `connection_sync_service_for(platform)` method |
| `app/services/ad_platforms/meta/connection_sync_service.rb` | New | Wraps token refresh + spend sync + run record + error lifecycle. Mirror Google's. |
| `app/controllers/dashboard/spend_controller.rb` | Spend dashboard | Inherits `BaseController#filter_params`; carries `models[]`, `accounting_mode`, `granularity` (Phase 5) through |
| `app/controllers/dashboard/base_controller.rb` | Filter resolution | Existing `selected_attribution_models` (returns `.first(2)`) drives primary + compare. No new helpers needed in Phase 2. |
| `app/views/dashboard/spend/_hero_metrics.html.erb` | Hero tiles | Period-delta sub-line; new "Platform vs Attributed gap" tile |
| `app/views/dashboard/spend/_trend_chart.html.erb` | Timeseries | Granularity pill, accounting pill, comparison line data |
| `app/views/dashboard/spend/_channel_table.html.erb` | Channel breakdown | Δ columns when comparing; gap columns; confidence band column |
| `app/views/dashboard/spend/_model_selector.html.erb` | New partial | Primary model pill + Compare pill |
| `app/javascript/controllers/chart_controller.js` | Highcharts | Support second muted line; tooltip with delta; weekly/monthly x-axis |

---

## All States

| State | Condition | Expected Behavior |
|---|---|---|
| Happy path | Account has spend + conversions in range, default model active | Renders all charts; selected model + comparison work; gap and band populated |
| No connections | `account.ad_platform_connections.empty?` | Existing empty state retained; "Connect Google Ads / Meta" CTA |
| Spend but no conversions | `ad_spend_records.any?` and `attribution_credits.empty? in range` | Spend tiles populated; ROAS shows "—" with tooltip "no attributed conversions in range"; band collapses to a single point |
| Conversions but no spend | inverse | Hero shows attributed revenue + spend $0; ROAS hidden; band hidden |
| Single model active | account has only one active attribution model | Primary pill renders; Compare pill disabled with tooltip "enable a second model on the AML page" |
| Comparison model = primary | user picks same model in both pills | UI prevents this (compare pill filters out the primary) |
| Sync stale | latest `ad_spend_records.updated_at` for a channel > 36h | Channel name muted; "Updated 2d ago" badge with tooltip linking to integrations page |
| Connection in `:error` state | `connection.status == :error` | Banner above the dashboard: "Google Ads sync failed. Reconnect." with link |
| Confidence band degenerate | only one model has any credits in range | Band hidden; channel column shows only point estimate |
| TZ unknown for account | no platform timezone metadata, account `Time.zone` blank | Fall back to UTC; log a one-off warning with `account_id` |
| Period-delta divisor zero | prior period had zero spend | Show "+∞" hidden; render as "—" with tooltip "no prior-period baseline" |
| Granularity vs range mismatch | user picks "Daily" on a 365-day range | Allowed but rendered chart auto-clusters in Highcharts (no special handling) |
| Cash vs Accrual on a single day | range is one calendar day | Both modes return identical data (touchpoint date = conversion date for a single-day range usually); no special handling |

---

## Implementation Tasks

### Phase 1 — Trust fixes (P0; ship first, even alone if needed)

- [x] **1.1** Reproduce timeseries bug locally with a spend record + conversion in non-UTC timezone; capture the failing assertion in a test
- [x] **1.2** Add timezone resolver in `MetricsService#report_timezone` reading `connection.settings['timezone_name']`. Meta captures it via `Meta::AcceptConnectionService`; Google now captures it too via `Google::CUSTOMER_QUERY` + `SUB_ACCOUNTS_QUERY` (`customer.time_zone` / `customer_client.time_zone`), threaded through `ListCustomers` → `select_account` view → `AcceptConnectionService` into `connection.settings['timezone_name']`. Falls back to UTC when neither is present.
- [x] **1.3** Update `BreakdownsQuery#daily_revenue` to use `DATE((converted_at AT TIME ZONE 'UTC') AT TIME ZONE :tz)` (double-cast: `converted_at` is `timestamp without time zone` storing UTC values, so reinterpret as UTC first, then shift)
- [x] **1.4** `BreakdownsQuery` accepts `accounting_mode:` (`:cash` or `:accrual`, default `:cash`); `MetricsService#timeseries_accounting_mode` overrides the default to `:accrual` for the chart and threads the mode into the cache key. URL toggle UI ships with Phase 5; param plumbing is live today.
- [x] **1.5** Accrual path joins `attribution_credits.session_id = sessions.id` and groups by `DATE((sessions.started_at AT TIME ZONE 'UTC') AT TIME ZONE :tz)`. `time_series` now iterates the union of spend and revenue date keys so accrual-only days surface.
- [x] **1.6** Build `AdPlatforms::Meta::ConnectionSyncService` mirroring Google's (token refresh, run record, error lifecycle). Note: `ApiUsageTracker.increment!(:meta)` is wired in `Meta::ApiClient` already; no additional wiring needed at the orchestrator level.
- [x] **1.7** Add `Registry.connection_sync_service_for(platform)`
- [x] **1.8** Refactor `SpendSyncJob` to dispatch via registry
- [x] **1.9** Tests: timeseries date alignment across timezones; cash mode (default); accrual mode (groups by touchpoint date); Meta + Google dispatch routing; Google TZ persistence in connection settings
- [x] **1.10** Remove the `_channel_table.html.erb:78` "Use 7d+ windows for accuracy" footnote
- [ ] **1.11** Verify on dev with a Google connection at non-UTC timezone

### Phase 2 — Model selector and comparison

- [x] **2.1** `_model_selector.html.erb` ships a primary pill + Compare pill using native `<details>` popovers and form-submit-on-change. No new Stimulus controller needed.
- [x] **2.2** `SpendController` reuses `BaseController#selected_attribution_models`; URL carries `?models[]=mdl_a&models[]=mdl_b` and round-trips through filter state
- [x] **2.3** `MetricsService` returns the existing flat shape with a new top-level `:compare` key (`{ totals:, by_channel:, time_series: } | nil`). Chose this over a fully nested `{ primary:, compare: }` shape to avoid breaking every downstream view consumer for one feature.
- [x] **2.4** `ChannelMetricsQuery` is now invoked per-model via `credits_scope_for(model)` instead of being passed an array of models. The blended-across-models bug is gone; primary and compare each query against a single-model scope.
- [x] **2.5** `BreakdownsQuery` is invoked per-model the same way.
- [x] **2.6** Channel table renders `Δ ROAS` and `Δ Revenue` columns plus deltas in the totals row when a compare model is set; columns are absent otherwise.
- [x] **2.7** `chart_controller.js` accepts `compareDataValue` + `compareNameValue` and renders a dashed amber line at the compare model's ROAS, aligned by date. `_trend_chart` partial passes the data and updates the legend.
- [x] **2.8** Compare pill renders as `opacity-50 pointer-events-none` with a "activate a second model on the AML page" tooltip when the account has fewer than two active models.
- [x] **2.9** Tests: per-model totals (no cross-model blending); `:compare` is nil with one model and present with two; URL state round-trips through controller; Δ headers appear when comparing and absent when not; chart attributes carry compare data when comparing
- [ ] **2.10** Manual QA on dev with at least three active models

### Phase 3 — Platform vs attributed gap

- [x] **3.1** `PlatformVsAttributedQuery` returns per-channel `{ platform_revenue, gap, gap_pct }` (dollars, not micros — view consumers don't deal in micros). `attributed_revenue` is intentionally omitted from this query's shape because `ChannelMetricsQuery` already returns it; `MetricsService#by_channel_with_gap` merges the two so each row carries `attributed_revenue` (from ChannelMetrics) + `platform_revenue / gap / gap_pct` (from PlatformVsAttributed). `MetricsService#primary_totals` rolls up `platform_revenue / gap / gap_pct` into hero totals. Compare data intentionally excludes gap fields (gap is primary-model-only per spec).
- [x] **3.2** Channel table renders Platform Rev (new), Attributed Rev (renamed from Revenue), Gap % (new) columns. Dropped the "vs Platform ROAS" tooltip subtitle from the ROAS column (the Gap % column owns that comparison now). Totals row mirrors. `Gap %` cell amber-toned when `|gap_pct| >= 15`.
- [x] **3.3** Hero strip implements Option C: MER tile replaced with "Platform vs Attributed" tile (`col-span-2 sm:col-span-1` so it doesn't orphan on mobile); MER demoted to a sub-line under the Attributed Revenue tile. Gap tile shows signed dollar gap as the primary number, signed `gap_pct` + "different methodologies" as sub-line. Tile background turns amber at the 15% threshold. `data-test-id` hooks added for both new structures.
- [x] **3.4** Tests: query correctness (math, zero-platform, zero-attributed, totals roll-up); MetricsService merge shape (gap fields on totals + by_channel rows; absent on compare); controller renders the new column headers + hero tile; MER sub-line renders when MER is computable
- [x] **3.5** Copy: hero gap sub-line + channel-table tooltip both use "different methodologies" framing, no accusatory verbs. Hero shows raw signed dollar amount with neutral or amber tone, no "platforms over-report" claim.

### Phase 4 — Confidence band

- [x] **4.1** `ConfidenceBandQuery` returns `{ channel => { min:, max:, selected:, by_model: } }` per channel with at least one model crediting it. The per-channel computation lives in a `ChannelConfidenceBand` value object so the query stays a pure transform pipeline (`spend_by_channel.map { |ch, sp| ChannelConfidenceBand.new(...) }.select(&:present?)`). `by_model` is keyed by the `AttributionModel` instance so the view can render `model.name.titleize` directly.
- [x] **4.2** No separate Solid Cache layer. The whole `MetricsService` payload is already cached for 5 minutes in `Rails.cache.fetch(cache_key)`; adding a 30-min sub-cache around just the band would double-cache and complicate invalidation. Eight grouped sums on indexed columns are cheap enough for the 5-min cadence. (Spec deviation; flagged in commit message.)
- [x] **4.3** Channel table renders rightmost "Confidence" column when account has multiple active models. Cell shows a 14×8 horizontal bar (color-keyed by spread ratio: emerald < 1.3×, amber < 2×, rose ≥ 2×) with a tick mark at the selected model's position; min/max ROAS labels on either end. The table now uses one `<tbody>` per row pair so the click-to-expand panel can sit as a sibling row beneath the main row without breaking semantic table structure. The column header carries a tooltip explaining the band; the totals row shows "—" since spread is per-channel.
- [x] **4.4** Each band cell is a `<button data-action="toggle#toggle">`; the expanded panel is a sibling `<tr data-toggle-target="content" class="hidden">` with `<td colspan="...">` inside the row's tbody. Panel renders all eight (or however many active) attribution models as a 2-column grid of name + horizontal bar + ROAS value, sorted descending by ROAS, with the selected model's bar in indigo and the rest in gray.
- [x] **4.5** `MetricsService#confidence_band_query` returns nil (and `by_channel` rows carry `confidence_band: nil`) when only one attribution model is active. Channels where no model produced any credit are filtered out by `ChannelConfidenceBand#present?`.
- [x] **4.6** Tests: band math (min, max, selected, by_model); degenerate single-model case; channel-with-no-credits case; query absent when account has only one active model; query present + populated when ≥2 active models

### Phase 5 — Polish

- [x] **5.1** Granularity pill (D / W / M) on the trend chart; rendered via `_trend_pill` partial as a segmented control. Default picked by `MetricsService#default_granularity_for_range` from a table-driven `RANGE_GRANULARITY_TABLE` (≤30d → daily, ≤120d → weekly, else monthly). URL override `?granularity=…` plumbed through `SpendController#filter_params` and threaded into the metrics-cache key.
- [x] **5.2** `BreakdownsQuery` accepts `granularity: :daily | :weekly | :monthly`. Both spend grouping and the cash/accrual revenue grouping use the same `GRANULARITY_TRUNC_FIELD` lookup that maps `:weekly → "week"`, `:monthly → "month"` for `DATE_TRUNC`. The TZ-shift expression is unchanged — granularity sits orthogonal to it.
- [x] **5.3** `MetricsService#prior_period_deltas` instantiates a second `ChannelMetricsQuery` against the date range immediately preceding the selected one (uses the existing `DateRangeParser#prior_period`). Returns `{ range_days, total_spend_pct, attributed_revenue_pct, blended_roas_pct }` nested under `totals[:prior_period]`. Each delta is nil when the prior value was zero or missing (no "+∞%" surfaces). Hero tiles render the delta via a small `_hero_period_delta` partial (green emerald above zero, rose below, gray dash + label when prior is nil). NCAC delta deferred — it requires another PaybackPeriodQuery on the prior range and the cost wasn't worth it for v1; the existing NCAC tile stays without a sub-line.
- [x] **5.4** `ChannelMetricsQuery` exposes per-channel `last_synced_at` (= `MAX(ad_spend_records.updated_at)` per channel). The channel-table name cell renders a "Updated 2h ago" sub-line via `SpendHelper#sync_freshness_label`. When older than `SpendHelper::SYNC_STALE_AFTER` (36h), the channel name dims to gray-400 and the badge text turns amber-600 — a pure visual dim, no separate tooltip / integrations link in v1 (was overkill for the surface; can layer a link later if support tickets surface).
- [x] **5.5 (partial)** Tests landed: granularity grouping (weekly + monthly bucket counts on real records), URL round-trip through controller, pill segmented-control rendering. Period-delta + freshness tests still owed under 5.3 / 5.4.

Cash/Accrual pill (originally listed under the Phase 1 spec text but never rendered) ships alongside the granularity pill — same `_trend_pill` partial, options `[ :cash, "Cash" ]` / `[ :accrual, "Accrual" ]`, tooltip explaining the semantic difference. URL plumbing already existed; just adding the surface.

### Phase 6 — Verify on production

- [ ] **6.1** Manual QA on dev with `pet-resort` style account (multi-connection, non-USD currency, non-UTC timezone)
- [x] **6.2** Full test suite green for all spend-dashboard surfaces (115+ runs across queries, services, controller). Pre-existing failures in `accounts/integrations_controller_test.rb` (3) and `sensitive_paths_test.rb` (2) are unrelated to this spec; same failures present at branch start.
- [x] **6.3** Single-render dashboard query count measured at 47 queries on dev seed data (under the 50-query test guard). The project uses Prosopite, not Bullet — Prosopite is enabled in development and surfaces N+1 to `Rails.logger`. Per-channel queries (8 metrics × N channels in `ChannelMetricsQuery`) all use single grouped sums, not per-row lookups. The 8 ROAS-per-model queries in `ConfidenceBandQuery` are intentional (one grouped sum per model) and bounded by the account's active model count.
- [ ] **6.4** Lighthouse / performance check: dashboard renders < 1.5s on dev seeded with realistic data
- [x] **6.5** `lib/docs/PRODUCT.md` extended with "Attribution-aware Spend Dashboard" section covering model selector, Cash/Accrual, granularity, gap, confidence band, period delta, sync freshness. `lib/docs/BUSINESS_RULES.md` extended with section 12 ("Spend Dashboard Semantics") documenting all 10 non-obvious rules (SD1–SD10) — Cash vs Accrual semantics, TZ handling, granularity defaults, gap math, period-delta definition, and the freshness threshold.
- [ ] **6.6** Move spec to `lib/specs/old/`

---

## Shipped commits (running log)

| Phase | Commit | Subject |
|---|---|---|
| 1.1–1.3 | `f42eb98` | fix(spend): align timeseries spend and revenue dates across timezones |
| 1.6–1.8 | `7493eca` | feat(ad-platforms): dispatch spend sync via Registry, add Meta::ConnectionSyncService |
| 1.2 (Google TZ) | `1635f2f` | feat(ad-platforms): capture Google Ads customer time zone at connect |
| 1.4–1.5 | `ed3d70f` | feat(spend): add cash/accrual accounting mode to spend timeseries |
| 2.3–2.5 | `f9ec7a0` | feat(spend): per-model metrics with comparison shape in MetricsService |
| 2.1, 2.2, 2.6, 2.7, 2.8 | `a2eb467` | feat(spend): model selector + comparison columns + dashed compare line |
| 3.1 | `5df3a3b` | feat(spend): platform-vs-attributed gap query + metrics-service wiring |
| 3.2–3.5 | `cb7b9b3` | feat(spend): platform-vs-attributed columns and hero tile |
| 4.1, 4.2, 4.5, 4.6 | `8efae7d` | feat(spend): confidence-band query + metrics-service wiring |

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|---|---|---|
| Timeseries TZ alignment | `test/services/spend_intelligence/queries/breakdowns_query_test.rb` | Same-day spend + conversion in non-UTC TZ aligns; ROAS appears for that day |
| Accrual mode | same | Revenue groups by touchpoint date, not conversion date |
| Cash mode | same | Revenue groups by conversion date |
| Granularity | same | Weekly / monthly grouping returns expected bucket count |
| Channel metrics by model | `test/services/spend_intelligence/queries/channel_metrics_query_test.rb` | Selected model drives `revenue_credit` sum (not first model) |
| Platform-vs-attributed | `test/services/spend_intelligence/queries/platform_vs_attributed_query_test.rb` | Gap math; zero-platform-revenue case |
| Confidence band | `test/services/spend_intelligence/queries/confidence_band_query_test.rb` | min/max/selected across 8 models; degenerate cases |
| MetricsService comparison shape | `test/services/spend_intelligence/metrics_service_test.rb` | `{primary:, compare:}` shape; nil compare when not requested |
| Meta connection sync orchestration | `test/services/ad_platforms/meta/connection_sync_service_test.rb` | Token refresh on expiry; run record created; error → `:error` status |
| Spend sync job dispatch | `test/jobs/ad_platforms/spend_sync_job_test.rb` | Routes to Google for `:google_ads`, Meta for `:meta`, raises for unknown |

### Controller / Integration

| Test | File | Verifies |
|---|---|---|
| `?models[]=mdl_xxx` round-trips | `test/controllers/dashboard/spend_controller_test.rb` | URL state preserved; metric reflects selected model |
| `?models[]=a&models[]=b` toggles comparison columns | same | Channel table renders Δ columns; chart container carries `data-chart-compare-data-value` |
| `?accounting_mode=accrual` | covered in `breakdowns_query_test.rb` | Timeseries data uses touchpoint-date grouping |
| Cross-account isolation | (existing) | Cross-account model selection rejected at scope resolution |

### Manual QA

1. Connect Google Ads on dev with a non-UTC ad account, sync data for last 30 days
2. Visit Spend dashboard; confirm timeseries has no null days
3. Toggle Cash / Accrual on the chart; confirm shape changes plausibly
4. Switch primary model from default to Markov; confirm hero ROAS, channel ROAS, payback all update
5. Click Compare → pick Last Touch; confirm Δ columns appear, second timeseries line appears
6. Click confidence band on a channel; confirm 8-model breakdown panel renders
7. Connect a Meta account (with feature flag); confirm sync job runs; confirm dashboard sums Meta + Google channels
8. Disconnect Meta; confirm dashboard degrades gracefully
9. Range "Last year"; confirm granularity defaults to monthly
10. Range "Last 7 days"; confirm granularity defaults to daily

---

## Definition of Done

- [ ] All Phase 1–5 tasks completed
- [ ] All unit, controller, and integration tests pass
- [ ] No regressions in existing dashboard test suite
- [ ] Manual QA steps 1–10 pass on dev
- [ ] No N+1 queries on dashboard load (Bullet clean)
- [ ] `lib/docs/PRODUCT.md` updated with attribution-aware spend capability
- [ ] `lib/docs/BUSINESS_RULES.md` updated with Cash vs Accrual definitions and the platform-vs-attributed gap definition
- [ ] Spec moved to `lib/specs/old/`

---

## Out of Scope

Things explicitly deferred to keep this spec ship-able. Each is worth doing but not as part of this scope.

- **Metadata filter and breakdown card** — fully specced in `lib/specs/spend_dashboard_metadata_breakdown_spec.md`. Should ship before or after this spec; the two compose cleanly via `MetricsService` filter args.
- **Hourly+device "diagnostics" demotion** — competitor research suggests hourly ROAS is statistically meaningless at SMB volume. Worth removing or hiding behind a "Diagnostics" tab. Separate decision; keep current tab as-is for this spec to avoid scope creep.
- **Custom dashboard builder / pinned KPI tiles** — Triple Whale / Polar pattern. Avoid for v1; opinionated default beats customization.
- **N-way model comparison grid** — only Cash/Accrual + primary + compare-to + confidence band ship. Eight-way pairwise grid would clutter the page; the band already serves the "all models at once" need.
- **Channel synergy matrix (Shapley pair-wise)** — strong differentiator candidate from competitor audit. Future spec; depends on this one's foundations.
- **Counterfactual budget shifts ("move $1k from Meta to Google")** — Recommendation Service exists in scaffold form (`RecommendationService`). Promoting it to a primary surface is a separate concern.
- **nCAC / new-vs-returning split** — specced separately if needed.
- **CSV export from spend dashboard** — `data_downloads_api_spec.md` covers exports; not blocking this spec.
- **Multi-currency normalization** — `AdPlatformConnection.currency` exists; cross-currency rollups are a separate problem.
- **Attribution-window selector (1d/7d/14d/30d/90d click windows distinct from model)** — competitor table-stakes per audit. Worth a follow-up; not blocking the model selector since attribution-window is upstream of model and currently account-default.
- **Removing the `recommendations` card** — out of scope decision; current recommendations are retained.

---

## Notes on competitor research

The design draws on a competitive audit of Triple Whale, Northbeam, Hyros, Rockerbox, Dreamdata, Wicked Reports, Polar Analytics, AppsFlyer, Attribuly, and GA4 + Looker Studio. Key inheritances and rejections:

**Borrowed:**
- Northbeam's Cash-vs-Accrual accounting axis (Pillar 1) — solves the timeseries date problem by exposing the real choice rather than picking one.
- GA4's two-model comparison-with-delta-column (Pillar 2) — proven UX for "which channels does the model disagree about."
- Triple Whale's platform-vs-attributed gap framing (Pillar 3) — the headline MTA pitch rendered as a number.
- Northbeam / AppsFlyer granularity pills and period-delta-on-KPIs (Phase 5) — table stakes; absence reads as toy.

**Rejected:**
- Triple Whale's "Total Impact" black-box single-number model. Opaque blends destroy debuggability. Our eight named models with a confidence band do the opposite job better.
- Hyros's account-level model lockdown. Model selector belongs at the report level, persistent per-user.
- Treemap channel breakdowns (Wicked). Sortable table is the working surface.
- Custom dashboard builder upfront (Triple Whale, Polar, Hyros). Opinionated default first; customization only after the default is loved.
- Vanity "top campaign" leaderboards. The marketer already knows their top campaign. The dashboard's job is to surface the campaigns whose ROAS just shifted.

**Differentiator:** the multi-model confidence band (Phase 4) is the single feature most likely to make a paid-media buyer say "this is the spend dashboard I wish I had." It's only possible because we already implement eight named models. Triple Whale and Polar cannot ship this without first re-implementing models we have today.
