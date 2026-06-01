# Custom Dimensions — Rule-Derived Campaign Attributes (All Platforms)

**Date:** 2026-05-31
**Priority:** P1
**Status:** Draft — awaiting approval to begin TDD
**Branch:** `feature/custom-dimensions` (off `develop`)
**Parent / context:** `lib/specs/spend_dashboard_metadata_breakdown_spec.md` (read-side consumer), `lib/specs/ad_platform_adapter_template_spec.md` (RowParser contract), `lib/specs/custom_channels_spec.md` (session-side sibling — see "Relationship to existing specs")

---

## Summary

Today an mbuzz account maps to a Google/Meta **customer account** (`AdPlatformConnection`), and the only business label you can attach to spend is a **single static key/value stamped on the whole connection** (`connection.metadata` → `ad_spend_records.metadata`, e.g. `location: Portland-Metro`). That breaks for the most common real-world shape: **one ad account whose campaigns span many locations / brands / regions**. An outdoor-gear retailer running `AcmeOutdoors | Portland | Search` and `AcmeOutdoors | Austin | PMax` in one Google account currently can't split spend by location at all — every row gets the same connection-level tag.

This spec adds **Custom Dimensions**: account-defined attributes (Location, Brand, Region, Product Line…) whose value is derived **per campaign** by an ordered list of **mapping rules** that match campaign fields (`campaign_name`, `campaign_type`, `network_type`, `platform_campaign_id`, `device`, `channel`) with operators (`equals`, `contains`, `starts_with`, `ends_with`, `regex`, `not_equals`). Resolved values are materialised into `ad_spend_records.metadata` at sync time and backfilled on rule change — so the existing per-connection metadata pipeline, and the "By Tag" breakdown dashboard, light up automatically.

It works **across every platform** that lands rows in `ad_spend_records` (Google + Meta today; LinkedIn/TikTok when their adapters ship).

The existing **`channel`** derivation (`CampaignChannelMapper`, with its exact-`campaign_id` `channel_overrides`) becomes the **first built-in Custom Dimension** — generalising "override channel for campaign 123" into "any campaign whose name matches `/display/i` → channel `display`", and collapsing two override mechanisms into one engine.

This is the answer to the question "we have mapping by account — what if we need to map by campaign?": you don't sub-divide the *tenant*; you derive *dimensions* on the spend rows the account already pulls.

---

## Prior art (why "Custom Dimensions" + "mapping rules")

Every serious marketing-data tool ships this exact feature and the vocabulary converges:

| Tool | Name | Output | Match mechanism |
|---|---|---|---|
| Funnel.io | **Custom Dimensions** + rules / lookup tables | a derived dimension | if-then on native fields; regex; code→name lookup |
| GA4 | **Custom Channel Groups** | a channel | ordered conditions: matches exactly / contains / begins / ends / regex; top-down; catch-all default |
| GTM | **Lookup / RegEx Table** variables | any value | input → output column, exact or regex |
| Improvado | **Naming Conventions** / governance | dimension parts + allowed-values dictionary | per-platform rule library + validation |

Shared model, which is exactly the ask: *a named output property, filled by ordered rules (match input field with an operator → assign value), first match wins, with a default.* GA4/GTM are the reference for the operator set + ordering + catch-all; Funnel for "a derived dimension reused everywhere downstream".

Sources: [Funnel custom dimensions](https://help.funnel.io/en/articles/1622167-custom-dimensions-explained-the-basics) · [Funnel lookup tables](https://help.funnel.io/en/articles/4279599-how-to-use-lookup-tables-when-creating-custom-fields) · [GA4 custom channel groups](https://support.google.com/analytics/answer/13051316?hl=en) · [GTM RegEx tables (Simo Ahava)](https://www.simoahava.com/analytics/the-regex-table-variable-in-google-tag-manager/) · [Improvado naming conventions](https://improvado.io/products/governance/naming-conventions)

---

## Current State (verified 2026-05-31 against schema + code)

### What exists and is built

- **`ad_spend_records`** stores spend at campaign granularity with these matchable fields per row: `platform_campaign_id`, `campaign_name`, `campaign_type`, `network_type`, `device`, `channel`, plus `metadata` (JSONB) and `spend_date`/`spend_hour`. (`db/schema.rb`)
- **Per-connection static metadata** is live end-to-end: `connection.metadata` → `RowParser#metadata_attrs` merges it onto every row (`app/services/ad_platforms/{google,meta}/row_parser.rb:31-32`); curated keys `location/region/brand/store` (`app/constants/ad_platform_metadata_keys.rb`); `MetadataNormalizer`, `MetadataLinkCheck`, `MetadataBackfillService` + `MetadataBackfillJob`; UI at `accounts/integrations/_metadata_panel.html.erb`.
- **Channel derivation** is the only *dynamic, per-campaign* mapping today: `AdPlatforms::Google::CampaignChannelMapper` (and the Meta one) map `campaign_type`/`network_type` → channel, with an **exact-`campaign_id`** override via `channel_overrides` (`{"campaign_123" => "display"}`), threaded sync service → row parser → mapper. There is **no UI** to populate `channel_overrides` — it defaults to `{}`.
- **Operator vocabulary** for matching already exists at `app/services/dashboard/scopes/operators/{base,equals,contains,not_equals,greater_than,less_than}.rb` — `{field:, values:, operator:}` applied to AR scopes (SQL), supporting columns and JSONB. **This is the engine to reuse.** It builds SQL `WHERE`; it has no scalar `matches?` and no `starts_with`/`ends_with`/`regex`.

### What is drafted but NOT built (verified absent from schema/models/services)

- `custom_channels` / `channel_rules` tables and `ChannelRules::*` services (`custom_channels_spec.md`) — **not built**.
- `metadata_breakdown_query.rb` / `known_dashboard_metadata.rb` (`spend_dashboard_metadata_breakdown_spec.md`) — **not built**.
- `connection.settings.campaign_overrides` for *metadata*: referenced as "plumbing in place" in specs, but the row parser's `metadata_attrs` merges only `connection.metadata`. The only real per-campaign override is `channel_overrides`, channel-only. **Treat per-campaign metadata as greenfield.**

### The gap

There is no way to derive a *business attribute* per campaign. The static connection tag is all-or-nothing; the one dynamic mechanism (`channel_overrides`) is channel-only, exact-ID, and has no UI. Customers with one ad account spanning many locations/brands cannot slice spend.

---

## Proposed Solution

### Concepts

- **Custom Dimension** — an account-scoped named attribute (`key` like `location`, display `name` like "Location"), with a `mapping_mode`, a **required** `default_value` (defaults to `"Other"`), and (in campaign mode) an ordered set of rules. One row in `custom_dimensions`. `channel` is a **built-in** dimension (see below).
- **Mapping Rule** — an ordered condition belonging to a campaign-mode dimension: *match `match_field` with `operator` against `value` → assign `output_value`*. First matching rule (by `position`) wins; if none match, the dimension's `default_value` applies. **There is always a fallback** — a campaign never ends up untagged for an active dimension.
- **Resolution** — given a campaign's fields, produce `{ dimension.key => resolved_value }` for every active dimension. Merged onto `connection.metadata` and written to `ad_spend_records.metadata` at sync; the built-in `channel` dimension additionally writes `ad_spend_records.channel`.

### Mapping granularity (by account vs by campaign)

A dimension is mapped at one of two granularities, chosen per dimension and switchable. Both are managed under one **"Map attributes"** hub (the entry point); see the mockups `lib/mockups/map_attributes.html` (hub + chooser + by-account editor) and `lib/mockups/custom_dimensions.html` (by-campaign rules editor).

- **By account** (`mapping_mode: "account"`) — one fixed value per ad-platform connection, applied to every campaign in that account. This **is** the existing `connection.metadata` feature, now defined by a dimension: the dimension owns the `key`, and the by-account editor sets `connection.metadata[key]` per connection. Fast path for the account-per-location shape. No rules.
- **By campaign** (`mapping_mode: "campaign"`) — `dimension_rules` derive the value per campaign. For the one-account-spans-many shape.

**They compose, and account is the baseline.** At sync the resolver layers campaign-rule output over the by-account values: `connection.metadata.merge(campaign_resolved)`. So a dimension that is by-account contributes its per-connection value; a by-campaign dimension contributes its rule output, falling back to `default_value`. A connection's by-account value also acts as the fallback for a same-key by-campaign dimension where no rule matches, before `default_value`.

This unifies the two pre-existing mechanisms (static `connection.metadata`, per-`campaign_id` `channel_overrides`) under one model rather than leaving them as disconnected features. By-account editing **moves into** the Map attributes hub; the integrations detail page keeps a deep-link to it (decided 2026-05-31).

### Data flow

```
Spend sync (per platform)
  RowParser builds the campaign row (campaign_name, type, network, device, id, channel)
    → CustomDimensions::Resolver(account, row) → { "location" => "Portland", "brand" => "Acme" }
    → metadata = connection.metadata.merge(resolved)        # rule-derived overrides win
    → channel = resolved channel (built-in dimension)        # supersedes channel_overrides
  upsert ad_spend_records

Rule created / updated / deleted
  → CustomDimensions::BackfillJob(account)
    → recompute resolver over existing ad_spend_records (fields already stored on each row — no API re-pull)
    → update_all metadata (and channel for the built-in dimension)

Dashboard (spend_dashboard_metadata_breakdown_spec — read side)
  → groups ad_spend_records.metadata->>'location' → spend/revenue/ROAS per value (unchanged; just works)
```

Materialise-at-sync (not resolve-at-query) is the deliberate choice: it reuses the live `metadata` pipeline + `MetadataBackfill*`, keeps dashboard reads trivial (`metadata->>'key'`), and means the drafted breakdown card needs **zero** changes to consume dimensions. Backfill is cheap because `ad_spend_records` already stores every field a rule matches on, so recomputation never touches the platform API.

---

## Data Model

### `custom_dimensions` table

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `account_id` | bigint FK | Multi-tenancy, `NOT NULL` |
| `key` | string | Metadata key written to `ad_spend_records.metadata`, lowercased/normalised (reuse `MetadataNormalizer`). e.g. `location` |
| `name` | string | Display name. e.g. "Location" |
| `default_value` | string | Value when no rule matches. `NOT NULL`, defaults to `"Other"`. Every campaign always resolves to a value — there is no "untagged" row. User can change it to anything (or to a built-in default-resolver for `channel`) |
| `mapping_mode` | string | `"account"` or `"campaign"`. `NOT NULL`, defaults to `"campaign"`. **account** = one fixed value per ad-platform connection (reuses `connection.metadata[key]`); **campaign** = rule-derived per campaign (`dimension_rules`). See "Mapping granularity" |
| `platform` | integer (nullable) | Scope to one `AdPlatformConnection.platform`; NULL = all platforms |
| `position` | integer | Display/eval order among dimensions (independent dimensions, but stable ordering) |
| `is_active` | boolean | Default `true` |
| `built_in` | string (nullable) | Non-null marks a system dimension with a default resolver. v1: `"channel"`. NULL = user-defined |
| `created_at` / `updated_at` | datetime | |

- Unique index: `(account_id, key)`
- Index: `(account_id, is_active)`
- Prefix: `cdim_`
- `key` validated against `MetadataNormalizer`; user-defined `key` must not equal a `built_in` key (`channel`).
- Curated `key` suggestions reuse `AdPlatformMetadataKeys::CURATED` (location/region/brand/store) in the picker; free text allowed.

### `dimension_rules` table

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `account_id` | bigint FK | Multi-tenancy, `NOT NULL` (denormalised for backfill scoping) |
| `custom_dimension_id` | bigint FK | Parent dimension, `NOT NULL` |
| `position` | integer | Lower = evaluated first. First match wins |
| `match_field` | string | Campaign field to match (enum-as-string, see below) |
| `operator` | string | `equals` / `not_equals` / `contains` / `starts_with` / `ends_with` / `regex` |
| `value` | string | Pattern/literal to match against (regex source for `regex`) |
| `output_value` | string | Value assigned to the dimension when this rule matches |
| `created_at` / `updated_at` | datetime | |

- Index: `(custom_dimension_id, position)`
- Prefix: `drul_`
- `match_field` enum (maps to `ad_spend_records` columns):

  | `match_field` | Source | Platforms |
  |---|---|---|
  | `campaign_name` | `campaign_name` | all (primary) |
  | `campaign_id` | `platform_campaign_id` | all (exact targeting; supersedes `channel_overrides`) |
  | `campaign_type` | `campaign_type` | Google: SEARCH/DISPLAY/…; Meta: objective |
  | `network_type` | `network_type` | Google PMax only |
  | `device` | `device` | all |
  | `channel` | `channel` | all (derived channel; lets non-channel dimensions key off channel) |

- `regex` validation: compile with a size cap and reject catastrophic patterns at save time (see "Regex safety"). `value` length capped (e.g. 500 chars).

### No new columns on `ad_spend_records`

Resolved values land in the existing `metadata` JSONB (and `channel` for the built-in). The drafted breakdown dashboard already reads `metadata->>'key'`. No schema change to the spend table.

---

## Rule Engine — reuse `Dashboard::Scopes::Operators`

The matching semantics must be **one source of truth**, shared by dashboard filters (SQL) and dimension resolution (in-memory, per campaign string). Extend the existing operators rather than fork:

1. Add a class method `matches?(candidate, value)` to each operator (scalar, in-memory) alongside the existing `call(scope)` (SQL). One operator class, two evaluation modes. Semantics must agree (`contains` = case-insensitive substring in both).
2. Add the three operators marketers expect that don't exist yet: **`StartsWith`**, **`EndsWith`**, **`Regex`** (and confirm `Equals`/`NotEquals`/`Contains` cover the rest). `Contains` already encodes ILIKE; its scalar twin is `candidate.to_s.downcase.include?(value.downcase)`.
3. A thin dispatcher (`Operators.matches?(operator:, candidate:, value:)`) camelizes the operator → constant, mirroring the existing `safe_constantize` pattern.

`CustomDimensions::Resolver` then walks each active dimension's rules in `position` order, calls `Operators.matches?` against the row's `match_field` value, returns `output_value` on first hit, else `default_value`.

> Note: the drafted `custom_channels_spec.md` (session-side) defines a *separate* `match_operator` enum with no regex. To avoid a third operator implementation, that spec should adopt this shared `Operators` engine when it's built; this spec does not implement the session side (see below).

---

## Built-in `channel` dimension (unify decision) — DEFERRED (decided 2026-06-01)

**Status: deferred to a later spec.** User dimensions (Phases 1–3) ship without touching channel; `CampaignChannelMapper` is left exactly as-is. Rationale: channel unification is the one phase that rewrites the live spend-sync `channel` derivation, and it's wanted but not urgent. The model already carries `built_in`, so picking it up later is additive.

**Captured requirements for when we build it** (from the deferral discussion):

- This is a genuinely wanted feature: let users map **rules (campaign attributes) and URLs** to channels, **existing or brand new**.
- **New channels, not just `Channels::ALL`.** Users will want to coin channels like `ai_paid`. So channel-rule `output_value` must NOT be hard-constrained to `Channels::ALL` — it intersects `custom_channels_spec.md` (custom channel definitions + chart colours). Resolve that overlap before building: a channel rule's output may be a *custom* channel the account defined.
- **The type→channel default map is too coarse.** "It's Google Ads" does not mean it's auto search/display/video. Google's newer types (e.g. **AI Max** → `ai_paid`), Performance Max, retargeting, etc. should be user-remappable. The built-in `CampaignChannelMapper` default is only a starting point users override per their taxonomy.
- **Two surfaces, one idea.** Campaign-attribute → channel is spend-side (this spec's engine). URL/landing-page → channel is visit-side (`custom_channels_spec.md`, matches `landing_page_path` etc.). Both should share the operator engine; design them together so "channels" means one thing.

**Original design (preserved for the later spec):** `channel` becomes a seeded, `built_in: "channel"` dimension per account:

- **Default resolution** stays in `CampaignChannelMapper` (type/network → channel maps) — exposed to the resolver as the dimension's "default value provider" so out-of-the-box behaviour is unchanged.
- **User rules** on the channel dimension run *first*; a matching rule's `output_value` (a `Channels::ALL` slug, validated) overrides the default. This generalises today's exact-`campaign_id` `channel_overrides` into name/regex/type matching, and gives `channel_overrides` the UI it never had.
- The legacy `channel_overrides` param path is migrated: existing exact-ID overrides (none in prod today, since no UI populated them — verify before migration) map to `campaign_id` + `equals` rules. The `channel_overrides:` kwarg on the sync services/`CampaignChannelMapper` is removed once the resolver owns channel.
- `output_value` for the channel dimension is constrained to `Channels::ALL`; for user-defined dimensions it's free text.

This is the larger blast radius (touches live spend sync + `CampaignChannelMapper`), so it is its own phase, shipped behind the same flag and verified against a real sync before the override path is deleted.

---

## Regex safety

User-supplied regex is the one real risk (the session-side spec punted on regex for exactly this reason). Mitigations:

- Validate at save: compile the pattern, reject on `RegexpError`; cap source length (500); reject patterns with obvious catastrophic backtracking heuristics (nested unbounded quantifiers) — fail closed with a clear form error.
- Evaluation is **in-memory at sync/backfill**, never in user-facing request SQL, and only against short campaign-name strings — so worst case is a slow background job, not a blocked web request or a DB regex scan.
- Match with `Regexp.new(value, Regexp::IGNORECASE)` and a guard; treat a raised error during resolution as "no match" and log, so one bad rule can't abort a sync.

---

## Resolution & Backfill

### Resolver (pure, per row)

```
CustomDimensions::Resolver.new(account_dimensions).call(row)
  # row responds to campaign_name, platform_campaign_id, campaign_type, network_type, device, channel
  # returns { "location" => "Portland", "brand" => "Acme", ... } (channel handled by built-in path)
```

`account_dimensions` is loaded once per sync (not per row). Pure and memoisable — same input, same output — so it unit-tests without the DB and runs identically at sync and backfill.

### Sync-time (RowParser)

`metadata_attrs` becomes `connection.metadata.merge(resolver.call(row))` — rule-derived values win over the static connection tag. Both Google and Meta row parsers call the same resolver (resolver lives in `app/services/custom_dimensions/`, platform-agnostic).

### Backfill (rule change)

`CustomDimensions::BackfillService(account)` recomputes over existing `ad_spend_records` in batches — each row already carries `campaign_name`/`type`/`network`/`device`/`id`/`channel`, so resolution needs no API call. Mirrors the existing `MetadataBackfillService` (extend or compose with it). Enqueued by `CustomDimensions::BackfillJob` on any dimension/rule create/update/destroy. Clear-then-recompute keeps it idempotent and handles deletes (a removed dimension's key is stripped from `metadata`).

---

## Documentation

A how-to guide ships with the feature as a **`/docs` product page**, not an academy article: `app/views/docs/_custom_dimensions.html.erb`, whitelisted in `DocsController::ALLOWED_PAGES` and linked in the docs nav (`app/views/layouts/docs.html.erb`), served at **`/docs/custom-dimensions`**. (The `/docs` system is the product-help home — `getting-started`, `authentication`, `data-downloads`, etc. — distinct from the public SEO `academy`/`/articles`.) ✅ SHIPPED 2026-05-31.

The settings surface (Phase 5) links to it from the page header ("How mapping works" → `/docs/custom-dimensions`), matching both mockups. The page covers: the by-account vs by-campaign granularities, the always-a-fallback rule (`Other` default), writing and ordering mapping rules, the operator set, the built-in `channel` dimension, cross-platform reach, what re-tagging does on save, and where values surface (spend dashboard + data downloads).

## Relationship to existing specs

| Spec | Relationship |
|---|---|
| `spend_dashboard_metadata_breakdown_spec.md` | **Read side.** Its "By Tag" breakdown + metadata filter consume `ad_spend_records.metadata`. Custom Dimensions are the *write side* that finally makes those keys vary per campaign. Build order: this spec first (or together); the breakdown becomes far more useful once dimensions exist. |
| `custom_channels_spec.md` | **Sibling, different entity.** That spec maps *sessions/visits* (`sessions.effective_channel`); this maps *spend/campaigns* (`ad_spend_records`). They share the rule-engine concept. Recommendation: that spec adopts this `Operators` engine when built, retiring its bespoke `channel_rules` operator enum. Out of scope here — visits ≠ spend. |
| `ad_platform_adapter_template_spec.md` | RowParser is the integration point; new-platform adapters get dimensions for free by calling the shared resolver in their `metadata_attrs`. |

---

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Name | **Custom Dimensions** + **mapping rules** | Category-standard (Funnel/GA4); marketers know it; channel folds in as a built-in dimension |
| Where rules run | Materialise into `ad_spend_records.metadata` at sync; backfill on change | Reuses live metadata + backfill infra; trivial dashboard reads; breakdown card needs no change |
| Output storage | Existing `metadata` JSONB (+ `channel` for built-in) | No new spend-table columns; existing breakdown/filter consume it |
| Operator engine | Extend `Dashboard::Scopes::Operators` with `matches?` + StartsWith/EndsWith/Regex | One source of truth across SQL filters and in-memory resolution |
| Rule logic | Ordered, first-match-wins, per-dimension `default_value` | Matches GA4/GTM mental model; deterministic |
| Channel | **Deferred** (2026-06-01). User dimensions ship without touching channel; `CampaignChannelMapper` untouched | Channel rewrite is the only live-sync-altering phase; wanted but not urgent. Later work must also support new/custom channels (e.g. `ai_paid`) and remapping coarse Google types (AI Max, PMax), converging with `custom_channels_spec.md` |
| Regex | Allowed, validated, in-memory at sync/backfill only | Marketers expect it; kept off request-path SQL so it can't block web or DB |
| Cross-platform | Resolver is platform-agnostic; keyed on `ad_spend_records` fields | Works for Google + Meta now, LinkedIn/TikTok when adapters land |
| Backfill cost | Recompute from stored row fields, no API re-pull | `ad_spend_records` already has every matchable field |
| Account-level mapping | Keep it; fold into the dimension as `mapping_mode: "account"` under one "Map attributes" hub | Fast path for account-per-location; reuses shipped `connection.metadata`; one home instead of two disconnected features |

---

## All States

| # | State | Expected behaviour |
|---|---|---|
| 1 | Account has no dimensions | `metadata` = `connection.metadata` only; `channel` from default mapper. Zero overhead. Unchanged from today |
| 2 | One dimension, one rule, matches | Matching rows get `metadata->>'key'` = `output_value`. Breakdown card shows the slice |
| 3 | Multiple rules, ordered | First matching rule (lowest `position`) wins; later rules ignored for that row |
| 4 | No rule matches | Dimension's `default_value` applied (defaults to `Other`). Key is always present on the row; never unset |
| 5 | `regex` rule | Matched in-memory, case-insensitive; invalid pattern rejected at save |
| 6 | Dimension scoped to a platform | Only rows from that platform get the key; other platforms unaffected |
| 7 | Rule edited | Backfill recomputes affected rows from stored fields; dashboard reflects change after job |
| 8 | Dimension deleted | Backfill strips the key from `metadata` across rows; reverts cleanly |
| 9 | Built-in channel: user rule | Rule `output_value` (validated `Channels::ALL`) overrides default channel for matching campaigns; writes `ad_spend_records.channel` |
| 10 | Built-in channel: no user rule | Default `CampaignChannelMapper` behaviour — identical to today |
| 11 | `key` collides with `channel` | Validation rejects user-defined dimension using a built-in key |
| 12 | Two dimensions write different keys | Independent; both keys present on the row's `metadata` |
| 13 | New campaign appears mid-period | Resolved at next sync like any row; no special handling |
| 14 | Cross-account | Account A's dimensions never touch Account B's rows (every query `@account.custom_dimensions`) |
| 15 | Rule matches every row (broad) | Backfill runs in background, batched; no timeout |
| 16 | Bad regex at resolution time | Treated as no-match, logged; sync/backfill completes |

---

## Implementation Tasks

### Phase 1 — Operator engine (shared) ✅ SHIPPED 2026-05-31
- [x] 1.1 Add `matches?(candidate, value)` scalar mode to `Equals`/`NotEquals`/`Contains`
- [x] 1.2 New operators `StartsWith`, `EndsWith`, `Regex` (both SQL `call` and scalar `matches?`). Substring trio (`Contains`/`StartsWith`/`EndsWith`) refactored onto a shared `Operators::Like` base; each declares only its SQL `.pattern` + scalar `.matches?`. SQL literals and operator slugs extracted to constants in `operators.rb` (no magic strings)
- [x] 1.3 `Dashboard::Scopes::Operators.matches?(operator:, candidate:, value:)` dispatcher (camelize + safe_constantize; `respond_to?(:matches?)` guard so a new operator needs no further wiring)
- [x] 1.4 Tests: `test/services/dashboard/scopes/operators_test.rb` — every operator both modes, SQL↔scalar parity, regex safety guard, non-matchable/unknown return false. Green + `zeitwerk:check` clean + existing `filtered_credits_scope_test` unaffected

### Phase 2 — Data model ✅ SHIPPED 2026-05-31 (except 2.5, moved to Phase 4)
- [x] 2.1 Migration: `custom_dimensions` (incl. `mapping_mode` default `"campaign"`; unique `(account_id, key)`, prefix `cdim_`)
- [x] 2.2 Migration: `dimension_rules` (+ index `(custom_dimension_id, position)`, prefix `drul_`)
- [x] 2.3 `CustomDimension` model — inline (matches `ConversionDestination` house style, not concerns). `key` normalised via `MetadataNormalizer.normalize_key` (extracted for DRY reuse); uniqueness `(account_id, key)`; built-in key collision guard; `mapping_mode` string + inclusion; `platform` enum reuses `AdPlatformConnection.platforms`; scopes `active`/`by_account`/`by_campaign`/`for_platform`; predicates
- [x] 2.4 `DimensionRule` model — `operator` validated against `Dashboard::Scopes::Operators::MATCHABLE` (reused, single source); `match_field` inclusion; regex compiles guard; value length cap; `ordered` scope; rules valid only on `by_campaign` dimensions
- [ ] 2.5 Seed the `built_in: "channel"` dimension per account — **moved to Phase 4** (channel unification), where it becomes behaviourally meaningful. The model already supports `built_in`
- [x] 2.6 Tests: `test/models/custom_dimension_test.rb` + `dimension_rule_test.rb` (23 tests, validations + cross-account). Green, `zeitwerk:check` clean, `MetadataNormalizer` consumers unaffected. schema.rb dumped clean (no Timescale noise)

### Phase 3 — Resolution + materialisation
- [x] 3.1 `CustomDimensions::Resolver` — pure (no DB in `#call`); by-account → connection value else default, by-campaign → first matching rule (sorted by position) else connection value else default. Reuses `DimensionRule::ROW_ATTRIBUTES` + the shared operator engine. `.for_connection` loader scopes active/user-defined/for-platform dims with rules preloaded. SHIPPED 2026-06-01
- [x] 3.2 Wired into `Google::RowParser` + `Meta::RowParser` (`metadata_attrs` now `connection.metadata.merge(resolved)`, rules win); both `SpendSyncService`s build one resolver per sync via `Resolver.for_connection`. `resolver:` defaults to nil so behaviour is unchanged when an account has no dimensions. SHIPPED 2026-06-01
- [x] 3.3 `CustomDimensions::BackfillService` (account orchestrator) → `ConnectionBackfill` (per-connection re-materialise, `find_each`, recompute from stored row fields) + `BackfillJob`. Clear-then-recompute drops deleted-dimension keys; no API call. SHIPPED 2026-06-01
- [x] 3.4 Enqueue backfill on dimension/rule create/update/destroy via shared `EnqueuesDimensionBackfill` concern (both models) → `BackfillJob.perform_later(account_id)`. SHIPPED 2026-06-01
- [x] 3.5 Resolver tests + RowParser integration (merge + override) + backfill (recompute, idempotent, clear-then-recompute strips stale keys, cross-account isolation) + enqueue-on-change. 79 tests green across Phases 1-3; `zeitwerk:check` clean

**Phase 3 caveat (resolved in Phase 5.9):** `AdPlatforms::MetadataBackfillService` (run when an operator edits a connection's static metadata) still stamps `connection.metadata` only via `update_all`, so it would wipe rule-derived dimension keys until the next sync. Harmless today (feature flag off, no dimensions in prod), but when by-account editing moves into the Map attributes hub (5.9) that save path must run the dimension-aware `ConnectionBackfill` instead.

### Phase 4 — Channel unification — DEFERRED to a later spec (decided 2026-06-01)
Not built. Channel derivation stays as-is. When picked up, fold in the captured requirements above (new/custom channels, AI-Max-style remapping, shared engine with `custom_channels_spec.md`). Items below are the original plan, parked:
- [ ] 4.1 Route channel resolution through the built-in dimension: user rules first, `CampaignChannelMapper` default fallback
- [ ] 4.2 Write resolved channel to `ad_spend_records.channel` at sync; allow custom channels (reconcile with `custom_channels_spec.md`), not only `Channels::ALL`
- [ ] 4.3 Migrate any existing `channel_overrides` to `campaign_id`+`equals` rules (verify prod has none first), then remove the `channel_overrides:` kwarg path
- [ ] 4.4 Tests: default channel unchanged when no rules; rule override wins; legacy override equivalence

### Phase 5 — "Map attributes" hub UI (DESIGN_SYSTEM-conformant)
Mockups: `lib/mockups/map_attributes.html` (hub + chooser + by-account editor), `lib/mockups/custom_dimensions.html` (by-campaign rules editor).
- [ ] 5.1 `Accounts::CustomDimensionsController` (index/new/create/edit/update/destroy)
- [ ] 5.2 Routes under accounts namespace; add "Map attributes" to settings nav
- [ ] 5.3 Hub index: attributes with mapping badge (By account / By campaign), coverage, active toggle, edit
- [ ] 5.4 Granularity chooser (By account vs By campaign) on new attribute + "change" on existing
- [ ] 5.5 By-account editor: per-connection value inputs writing `connection.metadata[key]` (the existing metadata-panel behaviour, relocated into the hub)
- [ ] 5.6 By-campaign editor: key picker, default value, platform scope, nested rules (Turbo Frame add/remove), match_field/operator/value/output_value, reorder
- [ ] 5.7 Live "what would match" preview against the account's recent campaign names (read-only resolver run) — strongly recommended given regex
- [x] 5.8 Header link "How mapping works" → `/docs/custom-dimensions` (docs page shipped 2026-05-31; wire the link when the hub is built)
- [ ] 5.9 Move by-account metadata editing out of the integrations detail page; leave a deep-link from there to the hub
- [ ] 5.10 Tests: controller CRUD, by-account per-connection save, system test for create + reorder + preview + granularity switch

### Phase 6 — Polish & ship
- [ ] 6.1 Feature flag (`CUSTOM_DIMENSIONS`) gating UI + resolution
- [ ] 6.2 Full suite green; manual QA against a real multi-location Google account
- [ ] 6.3 Update `PRODUCT.md` / `BUSINESS_RULES.md`; flip `spend_dashboard_metadata_breakdown_spec.md` cross-reference; note channel unification in `custom_channels_spec.md`

---

## Out of Scope

- **Session-side dimensions** (`custom_channels` / visit channel rewrite) — separate entity; converge engines later.
- **Compound rules within a dimension** (AND across fields in one rule) — v1 is one field per rule, multiple rules per dimension. Revisit if needed.
- **Lookup-table import** (CSV of `campaign_name → value`) — manual rules only for v1; add if customers maintain large code→name maps.
- **Resolve-at-query-time** — materialise-at-sync chosen; revisit only if rule-edit backfill latency becomes a problem.
- **Per-campaign dimension UI beyond rules** (hand-tagging a single campaign) — expressible as a `campaign_id`+`equals` rule; no separate surface.
- **LinkedIn/TikTok** — automatic once their adapters write `ad_spend_records`; no work here.
- **Dimensions on conversions/sessions** — this spec is spend/campaign-side only.

---

## Open Questions

1. **`default_value` semantics for channel** — the built-in channel dimension's "default" is `CampaignChannelMapper`, not a static string. Model built-in default as a resolver hook rather than a `default_value` column value? (Leaning yes.)
2. **Preview data source** — recent distinct `campaign_name`s per account for the "what would match" preview; cap count and date window.
3. **Backfill granularity** — whole-account recompute vs per-dimension diff. Whole-account is simpler and idempotent; per-dimension is cheaper at scale. Start whole-account.
4. **Multi-key write ordering** — if two dimensions normalise to the same `key`, the unique index prevents it; confirm the validation message is clear.
