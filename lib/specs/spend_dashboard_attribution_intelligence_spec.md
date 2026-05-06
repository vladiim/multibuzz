# Spend Dashboard — Attribution Intelligence

**Date:** 2026-05-06
**Priority:** P0 (Spend dashboard is the second-most-visited dashboard surface; today it is structurally broken and competitively undifferentiated.)
**Status:** In Progress — Phases 1 and 2 shipped (TZ fix, accounting mode, Meta job dispatch, Google TZ capture, model selector + comparison mode + delta columns + dashed compare line); Phases 3–6 pending
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
> Pill at top of page: `Model: Time Decay`. They click it, see all eight models with sub-labels (Heuristic / Probabilistic). They pick Markov Chain. Hero ROAS recomputes from 3.2 to 2.7. Channel table re-sorts. Timeseries line redraws. URL now reads `?attribution_model=markov_chain` — they could share this view.

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
| B | Cast `converted_at` to the account's reporting timezone derived from `AdPlatformConnection.metadata['timezone']` (or fallback to account `Time.zone`), then take `DATE()` of that | Picked. Matches platform reporting semantics. Single SQL: `DATE(conversions.converted_at AT TIME ZONE :tz)` with `:tz` resolved per-account at query time. |

**Accounting mode toggle (Northbeam pattern).** Borrowed from the competitor audit. The "spend lags conversions" problem is real and the right fix is to expose the choice rather than pick one and hide it. Two modes:

- **Cash (default for hero KPIs)** — group revenue by `conversion.converted_at` date. Today's number is "what came in today," includes lag from yesterday's spend.
- **Accrual (default for timeseries)** — group revenue by the date of the *first touchpoint that received credit* in the conversion's journey. Single-day ROAS becomes "spend on day X attributed back to revenue from spend on day X."

Implementation: `AttributionCredit` already stores `revenue_credit` per touchpoint. Accrual mode joins through `Touchpoint.occurred_at` (or the equivalent journey-event timestamp) instead of `Conversion.converted_at`. Both queries get `AT TIME ZONE :tz` treatment.

A small toggle in the timeseries chart header (Cash | Accrual). Default Accrual on the chart, Cash on hero tiles. Persisted in the URL as a query param.

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

**Single model selector.** A pill in the dashboard header, alongside the existing date-range picker. Default = account's `is_default` attribution model. Switching the pill re-renders every metric on the page (hero tiles, channel table, timeseries, payback). State persisted in URL (`?attribution_model=time_decay`) so it survives reload and is shareable.

`SpendIntelligence::MetricsService` already accepts the param; we delete the "first-only" code path and pass the selected model through every query. `ChannelMetricsQuery`, `BreakdownsQuery`, and `HourlyDeviceMetricsQuery` need to accept `attribution_model:` and join `attribution_credits.attribution_model_id = ?`. `PaybackPeriodQuery` already does this.

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

### Data flow (proposed)

```
SpendController#show
  → filter_params (date_range, channels, attribution_model, compare_to, accounting_mode, granularity)
  → SpendIntelligence::MetricsService
      → ChannelMetricsQuery(model: primary)
      → ChannelMetricsQuery(model: compare_to)              [if comparison]
      → ChannelMetricsQuery × 8 models                       [for confidence band; cached]
      → BreakdownsQuery(model:, accounting_mode:, granularity:, tz: account.tz)
      → PaybackPeriodQuery(model:)
      → PlatformVsAttributedQuery(model:)                    [new]
      → Returns: { primary: {...}, compare: {...}, band_per_channel: {...}, ... }
  → View renders:
      - hero tiles (primary KPIs + period delta + platform-vs-attributed gap tile)
      - channel table (model + compare cols + gap cols + confidence band column)
      - timeseries (primary + compare lines, granularity toggle, Cash/Accrual toggle)
      - payback (primary model)
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
| `app/controllers/dashboard/spend_controller.rb` | Spend dashboard | Accept `attribution_model`, `compare_to`, `accounting_mode`, `granularity` params (and persist in URL) |
| `app/controllers/dashboard/base_controller.rb` | Filter resolution | `selected_attribution_model` and `compare_attribution_model` helpers |
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
- [x] **1.2** Add timezone resolver in `MetricsService#report_timezone` reading `connection.settings['timezone_name']` (Meta captures it; Google capture is a follow-up TODO, falls back to nil/UTC)
- [x] **1.3** Update `BreakdownsQuery#daily_revenue` to use `DATE((converted_at AT TIME ZONE 'UTC') AT TIME ZONE :tz)` matching the spend group by
- [x] **1.4** Add `accounting_mode` enum to `BreakdownsQuery` (`cash` and `accrual`, default `:cash`); `MetricsService` defaults the timeseries to `:accrual` and threads the mode into the cache key
- [x] **1.5** Accrual path joins `attribution_credits.session_id = sessions.id` and groups by `DATE((sessions.started_at AT TIME ZONE 'UTC') AT TIME ZONE :tz)`. `time_series` now iterates the union of spend and revenue date keys so accrual-only days surface.
- [x] **1.6** Build `AdPlatforms::Meta::ConnectionSyncService` mirroring Google's (token refresh, run record, error lifecycle). Note: `ApiUsageTracker.increment!(:meta)` is wired in `Meta::ApiClient` already; no additional wiring needed at the orchestrator level.
- [x] **1.7** Add `Registry.connection_sync_service_for(platform)`
- [x] **1.8** Refactor `SpendSyncJob` to dispatch via registry
- [x] **1.9** Tests: timeseries date alignment across timezones; Meta + Google dispatch routing. Accounting-mode tests pending 1.4/1.5.
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

- [ ] **3.1** `PlatformVsAttributedQuery` returning per-channel `{ platform_revenue_micros, attributed_revenue_micros, gap_micros, gap_pct }`
- [ ] **3.2** Add three columns to channel table: Platform Rev, Attributed Rev, Gap
- [ ] **3.3** Add hero tile "Platform vs Attributed" with tone color when gap >= 15% absolute
- [ ] **3.4** Tests: query correctness; tile copy on tone thresholds; gap when platform revenue is zero
- [ ] **3.5** Marketing-safe copy review on the gap framing (no accusatory language; "different methodologies")

### Phase 4 — Confidence band

- [ ] **4.1** `ConfidenceBandQuery` running ROAS per active model per channel, returning `{ min, max, selected }`
- [ ] **4.2** Cache result in Solid Cache keyed by `[account_id, range_start, range_end, channel_set, metadata_filter, models_signature]`, 30 min TTL
- [ ] **4.3** Channel table renders horizontal-bar column with band
- [ ] **4.4** Click on band expands inline panel with per-model values; reuse Stimulus toggle controller
- [ ] **4.5** Hide band when only one model has credits in range or only one model is active
- [ ] **4.6** Tests: band math (min, max, selected); cache invalidation on model addition; degenerate-state hiding

### Phase 5 — Polish

- [ ] **5.1** Granularity pill (D / W / M) on timeseries; default by range length
- [ ] **5.2** `BreakdownsQuery` supports `granularity: :daily | :weekly | :monthly`
- [ ] **5.3** Period delta on hero tiles (ROAS, Spend, Attributed Revenue, CAC)
- [ ] **5.4** Sync freshness badge per channel; tooltip linking to integrations page
- [ ] **5.5** Tests: granularity grouping; period-delta math when prior is zero; freshness threshold per platform

### Phase 6 — Verify on production

- [ ] **6.1** Manual QA on dev with `pet-resort` style account (multi-connection, non-USD currency, non-UTC timezone)
- [ ] **6.2** No regressions in existing controller tests
- [ ] **6.3** No N+1 in any query path (use Bullet locally during QA)
- [ ] **6.4** Lighthouse / performance check: dashboard renders < 1.5s on dev seeded with realistic data
- [ ] **6.5** Update `lib/docs/PRODUCT.md` (new "Attribution-aware spend" capability) and `lib/docs/BUSINESS_RULES.md` (Cash vs Accrual semantics, gap definition)
- [ ] **6.6** Move spec to `lib/specs/old/`

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
| `?attribution_model=` round-trips | `test/controllers/dashboard/spend_controller_test.rb` | URL state preserved; metric reflects selected model |
| `?compare_to=` toggles comparison columns | same | Channel table renders Δ columns; timeseries has two series in JSON payload |
| `?accounting_mode=accrual` | same | Timeseries data uses touchpoint-date grouping |
| Cross-account isolation | same (existing) | Selecting another account's model id 422s |

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
