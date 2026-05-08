# Spend Dashboard Bug Fixes (post Phase 1–5 UAT)

**Date:** 2026-05-08
**Status:** Draft
**Branch:** `fix/spend-dashboard-bugs`
**Parent:** `lib/specs/spend_dashboard_attribution_intelligence_spec.md` (Phase 6 UAT bugs)

## Problem

Three issues surfaced during visual UAT of the live `/dashboard/spend` page on a real account:

### Bug 1 — Empty-state CTA mislabels the destination and gets trapped in the turbo frame

`app/views/dashboard/spend/_empty_state.html.erb:14` already routes to `account_integrations_path` (correct), but:

- The button is hard-coded `Connect Google Ads` with the Google `G` icon, which lies about the destination — the integrations hub lets the user pick any platform.
- No `turbo_frame: "_top"` on the link, so the integrations page tries to render inside the `spend_<account_prefix_id>` turbo frame and breaks layout.

### Bug 2 — Compare-mode totals are wildly inconsistent with the timeseries and channel table

With the model selector set to `Linear` vs `First Touch` and channels filtered, the dashboard renders:

- Hero: Blended ROAS **57.91x**, Total Spend **$54,031**, Attributed Revenue **$3,128,741**, Platform vs Attributed **+$3,078,993 (+6189.2%)**
- Trend chart: **flat at zero** for both Linear and First Touch
- Channel table: Paid Search $53,939.38 / 26.17x, Display $91.17 / 0.0x, every other channel $0 / —

The hero implies $3.1M of attributed revenue. The channel table sums to roughly $1.4M (paid search ROAS × spend), not $3.1M. The timeseries reports zero per-day revenue for both models. The three queries that should agree on "attributed revenue in this date range under this model" disagree by 2–3×.

The +$3M / +6189% gap card is also a red flag on its own — production attribution should under-credit the platforms (negative gap), not over-credit them by 60×.

Most likely culprits to walk in `SpendIntelligence::MetricsService`:

- `primary_totals` and `compare_totals` may be aggregating credits from the *union* of both models when only one is requested per side, double-counting revenue.
- The timeseries query may be applying a model filter that the totals query is not.
- The channel-filter param may be applied inconsistently across the three sub-queries.
- `Platform vs Attributed` query may be using the wrong attributed-revenue input (e.g. summing both models' credits) producing the +$3M number.

### Bug 3 — "User properties" cannot be tested because the app is blocked from this state

User report: *"app is blocked so can't test if user properties is working"*. Awaiting clarification on (a) what "user properties" means in this context — visitor `properties` JSONB? metadata filter? something else? — and (b) what state the app is blocked in. Tracked here as a known unknown so we don't lose it; not actionable until clarified.

## Solution

Each bug is its own commit on this branch.

### Fix 1 — empty-state CTA

- Relabel `Connect Google Ads` → `Connect ad platform`.
- Replace Google `G` icon with a generic plug / arrow icon.
- Add `data: { turbo_frame: "_top" }` to the link helper so the integrations page renders at the top level.
- Update existing controller test if it asserts the old label.

### Fix 2 — compare-mode totals divergence

Investigation-first. Before changing code:

- Reproduce against dev seed with two models active and a channel filter applied.
- Diff the SQL emitted by `primary_metrics`, `compare_metrics`, `primary_breakdowns.time_series`, and `Queries::PlatformVsAttributedQuery` for the same model + channel + date range.
- Find the first place the row counts diverge.

Likely fix surface is `Scopes::CreditsScope` or one of the per-query model-filter applications. We pick the fix once the divergence point is known.

Add a regression test: with two models active and one channel selected, the sum of the channel table's `attributed_revenue` column equals `totals.attributed_revenue` to within rounding. Same for the trend chart's daily revenue sum.

### Fix 3 — user properties

Blocked on clarification. Not started.

## Acceptance Criteria

### Fix 1

- [x] Empty-state CTA reads `Connect ad platform`, no Google logo
- [x] Clicking the CTA navigates to `/account/integrations` at the top frame (no broken nested layout)
- [x] Existing empty-state test still passes (or is updated to match new copy)

### Fix 2

- [ ] Reproduction documented (params + expected vs actual numbers)
- [ ] Divergence point identified between `primary_totals`, channel-table sum, and `time_series` sum
- [ ] Regression test: with two models active + channel filter, `totals.attributed_revenue == by_channel.sum(:attributed_revenue)` (within rounding)
- [ ] Regression test: with two models active + channel filter, `totals.attributed_revenue == time_series.sum(:revenue)` (within rounding)
- [ ] Hero gap card shows a believable number (negative or low-positive single-digit-percent) on the seed account
- [ ] Existing 121 spend tests still pass

### Fix 3

- [ ] Clarification received from user on what "user properties" means and which state blocks the app
- [ ] Acceptance criteria filled in

## Out of Scope

- Phase 7 Scenario Modeling (`ad_spend_intelligence_spec.md`)
- Manual UAT items 6.1 / 6.4 from `spend_dashboard_attribution_intelligence_spec.md`
- Metadata breakdown spec (parked behind ad-platforms rollout)
- Demo dashboard polish (already shipped on `feature/demo-spend-polish`)
