# Spend Dashboard — Metadata Filter + Breakdown

**Date:** 2026-04-30
**Priority:** P1 — closes the "ROAS by location/plan/whatever" loop opened by `ad_platforms_meta_rollout_spec.md` Phase 3
**Status:** Draft — awaiting approval to begin TDD
**Branch:** new branch off `develop` after `feature/ad-platforms-meta-linkedin-rollout` lands
**Parent / context:** `lib/specs/ad_platforms_meta_rollout_spec.md`, `lib/specs/ad_platform_adapter_template_spec.md`

---

## Problem

Phase 4 of the ad-platforms rollout shipped per-connection metadata end-to-end at the data layer:

- Operators tag each ad-platform connection with a single key/value (`location: Eumundi-Noosa`, `plan_name: Pro`, etc.) at connect time and edit it from the connection's detail page (Phase 3.4)
- `MetadataNormalizer` lowercases keys and strips values; `MetadataLinkCheck` confirms whether the tag matches any conversions in the last 90 days
- `RowParser` merges connection metadata onto every `AdSpendRecord` at sync time (`ad_spend_records.metadata` JSONB)
- `MetadataBackfillJob` re-stamps historical rows when the operator edits the connection's metadata

But **the Spend dashboard (`/account/dashboard/spend`) has zero awareness of any of it**. Hero metrics (Blended ROAS, Total Spend, Attributed Revenue, NCAC, MER), the ROAS & Spend Trend chart, the By Channel breakdown, and the Channel Performance Detail all roll up across every connection in the account. A user with five Meta accounts (one per location) sees one blended number per metric and has no way to slice.

The metadata is fully populated and queryable. The dashboard is the missing yard.

---

## Goal

Surface metadata two ways on the Spend dashboard:

1. **Filter** — pick `?metadata_key=X&metadata_value=Y` and every metric / chart on the page reflects only that slice. Hero metrics, ROAS trend, By Channel, Hourly/Device, Payback Period, Recommendations, Channel Performance Detail. All scoped.
2. **Breakdown card** — a new "By {Tag}" card next to "By Channel" that groups all spend by metadata value, joins against conversions on the same property, and shows ROAS per slice without forcing the user to filter one at a time. (e.g. Sydney $X / 3.2x · Melbourne $Y / 2.8x · Brisbane $Z / 4.1x)

Both surfaces respect cross-account isolation, multi-tenancy, and the existing date-range / channel filters.

---

## Approach — two sub-phases on one branch

Sub-phase 1 ships the filter. Sub-phase 2 adds the breakdown card. Each is independently mergeable. Recommendation: ship both as one PR if scope holds, but keep them as two commits for clean history.

---

## Sub-phase 1 — Filter through `SpendScope`

**Goal:** filtering by metadata works across every existing surface without each surface needing its own query.

### Surface design

- New filter pill on the Spend dashboard header, alongside Channels / Date Range
- Pill renders as `Tag: location = Eumundi-Noosa` with an "x" to clear
- Click pill → small dropdown / popover offers the keys present on this account's connections (from `KnownMetadata.keys_for(account)` + already-tagged-on-spend-rows union) and, after a key is chosen, the values present for that key on existing `ad_spend_records`
- Empty state: when the user picks a key/value combo that has zero matching rows, dashboard shows "No spend matches the selected tag" (not "No data for this date range") so it's clear the filter is the cause
- URL params: `?metadata_key=location&metadata_value=Eumundi-Noosa` (flat, mirroring the connection edit form's shape)

### Files

| File | Change |
|---|---|
| `app/controllers/dashboard/base_controller.rb` | `filter_params` accepts `metadata_key` + `metadata_value` |
| `app/services/spend_intelligence/scopes/spend_scope.rb` | Adds `metadata_key:` / `metadata_value:` kwargs + `apply_metadata` step in the `.then` chain |
| `app/services/spend_intelligence/metrics_service.rb` | Forwards metadata params to `SpendScope` |
| `app/services/spend_intelligence/queries/*.rb` | All read from the scoped relation, so no per-query change needed (verify) |
| `app/views/dashboard/spend/_dashboard.html.erb` (or wherever filter pills live) | Adds the metadata filter pill |
| `app/services/spend_intelligence/known_dashboard_metadata.rb` | NEW pure service — surfaces (key → values) seen on `ad_spend_records.metadata` for this account, used to populate the picker |
| `app/javascript/controllers/metadata_filter_controller.js` | NEW — handles the key→values cascade in the picker; small Stimulus controller |

### Conversions side

The hero "Attributed Revenue" + "Blended ROAS" + "NCAC" metrics pull from `Conversion.attributed_*` paths, NOT from `ad_spend_records`. To compute correct ROAS-when-filtered, conversions must respect the same metadata filter — `where("properties->>:k = :v", ...)`.

Two options:

- **Option 1 (simple)** — apply the filter to both the spend scope AND the conversions scope used by the metrics service. Requires identifying every conversions-touching query inside `SpendIntelligence::MetricsService` and threading the filter through.
- **Option 2 (cleaner)** — wrap the conversions read in a `ConversionScope` analog to `SpendScope`, so the metadata filter is applied in one place. Larger refactor.

Recommendation: Option 1 in this sub-phase, Option 2 as a refactor if the read-paths multiply.

### Tests

| Test | Assertion |
|---|---|
| `SpendScope` — filters by metadata_key + value | Returns only rows where `metadata->>'<key>' = '<value>'` |
| `SpendScope` — ignores metadata params when both blank | No-op, returns same as without metadata |
| `SpendScope` — partial metadata params (key only or value only) | No-op (both required) — fail-safe |
| `Dashboard::SpendController` — round-trip with metadata params | Hero metrics + chart data reflect the filter |
| `Dashboard::SpendController` — metadata filter respects account isolation | Account A's filter cannot expose Account B's rows |
| `Dashboard::SpendController` — invalid metadata params (non-string) | Filter ignored or 422; no SQL injection |
| `KnownDashboardMetadata` — returns key→values map from existing rows | Empty when no rows; populated otherwise; deduped + sorted |

### Definition of Done (Sub-phase 1)

- [ ] Filter pill renders on `/account/dashboard/spend`
- [ ] Picking a key narrows the value picker to keys actually present in this account's data
- [ ] Hero metrics + trend chart + every breakdown reflect the filter
- [ ] Cross-account isolation tests pass
- [ ] Empty state explains "filter, not date range" when applicable
- [ ] No mocks added (per `feedback_no_mocks.md`)

---

## Sub-phase 2 — "By Tag" breakdown card

**Goal:** see ROAS by tag value at a glance without filtering one at a time.

### Surface design

- New card on the Spend dashboard, next to "By Channel"
- Header: "By Location" / "By Plan Name" / "By {selected key}". When the account has metadata under multiple keys, the header has a small key-picker dropdown
- Body: ranked list of values for the chosen key, showing per-row Spend, Attributed Revenue, ROAS, % of total spend
- Each row is clickable → applies the filter from Sub-phase 1 to drill in
- Empty state when the account has no metadata: "Tag your connections to see ROAS by location, plan, brand, etc. Set tags from any connection's detail page."

### Files

| File | Change |
|---|---|
| `app/services/spend_intelligence/queries/metadata_breakdown_query.rb` | NEW — groups `ad_spend_records.metadata->>{key}` and joins matching `Conversion` rows on `properties->>{key}` for revenue + ROAS per slice |
| `app/services/spend_intelligence/metrics_service.rb` | Adds `metadata_breakdown` to result hash when a key is selected (or the account has at least one populated metadata key) |
| `app/views/dashboard/spend/_metadata_breakdown.html.erb` | NEW partial — renders the card |
| `app/views/dashboard/spend/_dashboard.html.erb` | Renders the new partial alongside `_channel_summary` |
| `app/services/spend_intelligence/known_dashboard_metadata.rb` | Reused (Sub-phase 1) — drives the key-picker |

### Tricky bit: spend-vs-revenue join

Each row in the breakdown card is `(metadata_value, spend, revenue, roas)`. Spend comes from `ad_spend_records WHERE metadata->>'location' = 'Sydney'`. Revenue comes from `conversions WHERE properties->>'location' = 'Sydney'`. They join on the metadata value, not on a foreign key.

When a value exists on the spend side but not the conversion side: row shows `Spend: $X · Revenue: $0 · ROAS: 0` and gets a small "no matched conversions" badge — same UX as `MetadataLinkCheck.unlinked` on the connection detail page. Surfaces "you tagged spend but no SDK conversions match" without hiding the spend.

When a value exists on the conversion side but not the spend side: gets dropped from the card. Spend is the unit of analysis.

### Tests

| Test | Assertion |
|---|---|
| `MetadataBreakdownQuery` — single key, multiple values | Returns one row per value, spend + revenue + ROAS per row |
| `MetadataBreakdownQuery` — value with no matching conversions | Row exists with revenue=0, roas=0, `unlinked: true` flag |
| `MetadataBreakdownQuery` — accounts isolated | Account A's breakdown excludes Account B's data |
| `MetadataBreakdownQuery` — date-range filter respected | Same shape as existing channel queries |
| `MetadataBreakdownQuery` — channels filter respected | Composes with channel filter |
| `MetadataBreakdownQuery` — empty when account has no metadata | Returns empty; controller renders empty state, not the card |
| Controller integration test | Card renders for accounts with metadata, hidden for accounts without |
| Click-through test | Clicking a breakdown row appends the metadata filter to the URL and re-renders |

### Definition of Done (Sub-phase 2)

- [ ] Card renders next to By Channel when the account has at least one populated metadata key
- [ ] Key-picker shows when the account has metadata under multiple keys; absent when only one
- [ ] Per-row ROAS computes correctly across the date range
- [ ] Unlinked-value badge surfaces values where spend has no matching conversions
- [ ] Click-to-filter applies Sub-phase 1's filter inline (no full page reload, just a Turbo replace)
- [ ] Empty state with friendly "tag your connections" CTA
- [ ] Cross-account isolation tested in every query test

---

## Out of Scope (separate specs)

- **Multi-key compound filtering** — `?metadata=location=Sydney&metadata=brand=Premium` (AND across keys). Single key/value is the v1.
- **Per-campaign metadata overrides UI** — `connection.settings.campaign_overrides` already supports per-campaign metadata at the row-parser level; surfacing per-campaign overrides in the dashboard is a follow-up.
- **Saved filter presets** — "Show me Eumundi-Noosa anytime" as a named view. Bookmark URL works for now.
- **Compare-mode** — "Sydney vs Melbourne side by side" as a charting overlay. Useful but a separate widget.
- **Conversions tab metadata filter** — same shape as the Spend filter, applied to the Conversions dashboard. Worth adding when the spend version proves itself.

---

## Open Questions

1. **Which empty state wins when both date-range and metadata filter return zero rows?** Probably specific-to-cause: "No spend matches the selected tag in the last 30 days" combines both. Needs copy review.
2. **Picker UX for metadata keys** — dropdown vs typeahead. With the `KnownDashboardMetadata` service surfacing per-account keys, dropdown is fine until accounts have >10 distinct keys (unlikely).
3. **ROAS calculation** — gross attributed revenue / spend. Fine. But if the user has no attribution model active, attributed revenue is null. Card should fall back to "Configure attribution to see ROAS" CTA.

---

## Spec alignment automation (responding to a question)

The umbrella `ad_platforms_meta_rollout_spec.md` previously listed "ROAS-by-location dashboard widget" under Out of Scope with a forward reference. This spec is the answer to that forward reference.

**On automation:** spec drift is a real problem (CLAUDE.md: "Spec drift is tech debt. Update or archive.") but no current tooling auto-aligns specs. Possible future automation:

- Pre-commit hook that grep's modified files against spec checkboxes and warns if a `[ ]` looks done
- Periodic agent that diffs spec descriptions against current method signatures
- A linter that scans for forward references like `(see X spec)` and verifies X exists

None are trivially correct. For now: when a sub-spec lands, the umbrella's Out of Scope reference flips to "see {sub-spec}.md, ✅ done" by hand. This spec writeup is itself part of that loop.
