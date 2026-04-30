# Ad Platforms — Meta + LinkedIn Rollout

**Date:** 2026-04-28
**Priority:** P1
**Status:** Drafting — branch cut, awaiting approval to begin Phase 0
**Branch:** `feature/ad-platforms-meta-linkedin-rollout`

---

## Summary

Roll out Meta Ads and LinkedIn Ads adapters on top of the existing `AdPlatforms` adapter pattern proven by Google. Gate both behind per-account feature flags so production accounts only see them when explicitly enabled. Once both adapters are working and the pet-resort production account is on the allowlist, ship a per-connection metadata layer (`{ location: "sydney", ... }`) so multi-location businesses can roll spend up against conversions tagged with the same params. Close with an end-to-end test on the pet-resort account in production.

This spec is the umbrella. Each phase below ships its own sub-spec, RED→GREEN tests, and atomic commits on this one feature branch.

---

## Current State (verified 2026-04-28)

| Surface | State |
|---|---|
| `AdPlatformConnection` enum | Already includes `meta_ads:1, linkedin_ads:2, tiktok_ads:3` (`app/models/ad_platform_connection.rb:14`) |
| `AdPlatforms::BaseAdapter` | Defines `fetch_spend / refresh_token! / validate_connection` (`app/services/ad_platforms/base_adapter.rb`) |
| `AdPlatforms::Registry` | Only `:google_ads` registered (`app/services/ad_platforms/registry.rb:5-7`) |
| Plan-limit gate | Platform-agnostic via `can_add_ad_platform_connection?` — Meta/LinkedIn inherit cap automatically (called out in `integration_plan_limits_spec.md:192`) |
| Coming-soon UI | Meta + LinkedIn already render as `Soon` cards with Notify Me button |
| Feature-flag infra | **Does not exist** — no Flipper, no allowlist column, no `Account::FeatureFlags`. Phase 1 introduces it |
| Per-connection metadata | **Does not exist** — only `connection.settings.login_customer_id` and per-campaign `channel_overrides`. Phase 4 introduces it |
| LinkedIn API approval | Submitted 5 Mar 2026 (Development tier). Status to verify in Phase 0 |
| Meta API approval | App + Business Portfolio created. Business Verification was blocked on entity registration per `platform_api_approvals_spec.md:62`. Status to verify in Phase 0 |

---

## Approach

Five sequential phases on one branch. Each phase is independently mergeable to `develop` if we want to land partial work.

### Phase 0 — Verify external prerequisites

No code. Confirms we can actually build against real APIs before we cut a single line.

- [ ] **0.1** `bin/rails credentials:show` — confirm `meta_ads.app_id`, `meta_ads.app_secret`, `linkedin_ads.client_id`, `linkedin_ads.client_secret` are set for development AND production.
- [ ] **0.2** Meta: confirm Business Verification status in Meta Business Manager Security Centre. Confirm whether Advanced Access for `ads_read` has been granted, or whether we're still on Standard Access (development-only rate limits).
- [ ] **0.3** LinkedIn: confirm Advertising API (Development tier) has been approved on the LinkedIn developer portal. Note the approved scopes (expect `r_ads`, `r_ads_reporting`).
- [ ] **0.4** Update `lib/specs/platform_api_approvals_spec.md` with current status for both platforms. If either is not approved, document the blocker and pause this spec until unblocked.
- [ ] **0.5** Confirm the pet-resort production account ID and note it in 1Password (NEVER commit to git per CLAUDE.md hard rule).

**Exit criteria:** both platforms have working credentials and confirmed-approved API access, OR a documented decision to proceed against Meta sandbox / LinkedIn dev tier with explicit limitations recorded.

---

### Phase 1 — Feature-flag scaffolding

Sub-spec: `lib/specs/ad_platform_feature_flags_spec.md`

Account-level allowlist via dedicated table (option (a) from the proposal — queryable, audit-friendly).

| File | Change |
|---|---|
| `db/migrate/...create_account_feature_flags.rb` | NEW — `(account_id, flag_name, created_at)`, unique index `(account_id, flag_name)` |
| `app/models/account_feature_flag.rb` | NEW — minimal AR model, belongs_to `:account` |
| `app/models/concerns/account/feature_flags.rb` | NEW — `feature_enabled?(:meta_ads_integration)`, `enable_feature!(:foo)`, `disable_feature!(:foo)` |
| `app/models/account.rb` | Include `Account::FeatureFlags` |
| `app/controllers/admin/feature_flags_controller.rb` | NEW — admin-only toggle UI (list accounts, flip flag, audit who flipped it via existing admin auth) |
| `lib/tasks/feature_flags.rake` | NEW — `feature_flags:enable acct=acct_xxx flag=meta_ads_integration` for prod console use |
| `test/models/account/feature_flags_test.rb` | NEW — predicate, enable, disable, cross-account isolation |

**Flag names introduced this branch:** `:meta_ads_integration`, `:linkedin_ads_integration`.

**Gate locations (wired in Phases 2 & 3, scaffolding only here):**
- `Oauth::MetaAdsController#connect` — redirect to integrations page with "not enabled" notice if flag off
- `Oauth::LinkedinAdsController#connect` — same
- `app/views/accounts/integrations/show.html.erb` — only render the live connect cards when flag is on; otherwise show the existing "Coming Soon / Notify Me" card

**Tests:** model unit (predicate, enable, disable, isolation); admin controller test (only admins can flip); rake task smoke test.

---

### Phase 2 — Meta Ads adapter

Sub-spec: `lib/specs/ad_platform_meta_integration_spec.md`

Mirror Google's tree under `app/services/ad_platforms/meta/`.

| File | Mirrors |
|---|---|
| `app/services/ad_platforms/meta.rb` | `google.rb` — Graph API constants (v19.0), endpoints, scopes (`ads_read`), redirect URIs |
| `app/services/ad_platforms/meta/oauth_url.rb` | `google/oauth_url.rb` |
| `app/services/ad_platforms/meta/token_exchanger.rb` | `google/token_exchanger.rb` — short-lived → long-lived token exchange (Meta's two-step) |
| `app/services/ad_platforms/meta/token_refresher.rb` | `google/token_refresher.rb` (Meta long-lived tokens last 60 days; refresh = re-exchange) |
| `app/services/ad_platforms/meta/list_ad_accounts.rb` | `google/list_customers.rb` — `GET /me/adaccounts?fields=id,name,currency,account_status` |
| `app/services/ad_platforms/meta/accept_connection_service.rb` | `google/accept_connection_service.rb` — feature-flag re-check at top |
| `app/services/ad_platforms/meta/api_client.rb` | `google/api_client.rb` — Graph API requests with retry/backoff |
| `app/services/ad_platforms/meta/spend_sync_service.rb` | `google/spend_sync_service.rb` — `/{ad_account_id}/insights` with breakdowns: `[publisher_platform, device_platform, hourly_stats_aggregated_by_advertiser_time_zone]` |
| `app/services/ad_platforms/meta/row_parser.rb` | `google/row_parser.rb` — Meta micros use `spend` not `cost_micros`; convert via `MICRO_UNIT` |
| `app/services/ad_platforms/meta/campaign_channel_mapper.rb` | `google/campaign_channel_mapper.rb` — Meta campaigns map to `paid_social` by default; per-campaign overrides honored |
| `app/services/ad_platforms/meta/api_usage_tracker.rb` | `google/api_usage_tracker.rb` |
| `app/services/ad_platforms/meta/adapter.rb` | `google/adapter.rb` — registered in `AdPlatforms::Registry` |
| `app/controllers/oauth/meta_ads_controller.rb` | `oauth/google_ads_controller.rb` — same connect/callback/select_account/create_connection/reconnect/disconnect surface, `skip_marketing_analytics`, feature-flag gate up top |
| `app/views/oauth/meta_ads/select_account.html.erb` | `oauth/google_ads/select_account.html.erb` |
| `app/views/accounts/integrations/_meta_ads_card.html.erb` | `_google_ads_card.html.erb` |
| `app/views/accounts/integrations/_meta_ads_section.html.erb` | `_google_ads_section.html.erb` |
| `app/views/accounts/integrations/meta_ads.html.erb` | `google_ads.html.erb` |
| `app/views/accounts/integrations/meta_ads_account.html.erb` | `google_ads_account.html.erb` |
| `config/routes.rb` | Add `oauth/meta_ads/*` routes mirroring `oauth/google_ads/*`; add `get "meta_ads"` + `get "meta_ads/:id"` to `accounts/integrations` |
| `app/services/ad_platforms/registry.rb` | Register `meta_ads: AdPlatforms::Meta::Adapter` |
| `app/constants/ad_platform_channels.rb` | Add `META_CAMPAIGN_OBJECTIVE_MAP` if needed |
| `lib/tasks/ad_platforms.rake` | Extend dev/seed tasks |

**Tests:**
- Each service: outcome-based, no mocks. Hit Meta's sandbox or fixture-record real API responses. Per `feedback_no_mocks.md`, prefer integration over isolation.
- OAuth controller: feature flag gate, plan limit gate, account session pinning, race on create.
- End-to-end: `OauthFlowTest` style, walk a fixture account through connect → select → create → sync.
- Cross-account isolation in every test that creates a connection.

**Verification:** with `meta_ads_integration` flag enabled on a dev account, complete OAuth flow, confirm `AdSpendRecord` rows arrive for a 7-day window.

---

### Phase 3 — LinkedIn Ads adapter

Sub-spec: `lib/specs/ad_platform_linkedin_integration_spec.md`

Same shape as Phase 2, swapping LinkedIn-specific endpoints/scopes.

| Concern | LinkedIn specifics |
|---|---|
| API base | `https://api.linkedin.com/rest/` (Versioned API, header `LinkedIn-Version: 202404`) |
| Scopes | `r_ads`, `r_ads_reporting` (Development tier) |
| OAuth endpoints | `https://www.linkedin.com/oauth/v2/authorization` + `https://www.linkedin.com/oauth/v2/accessToken` |
| Account list | `GET /adAccounts?q=search` |
| Spend report | `GET /adAnalytics?q=analytics&pivots=List(CAMPAIGN)&timeGranularity=DAILY&dateRange=...` |
| Token lifetime | Access token 60 days; refresh tokens 365 days. Need refresh handling. |
| Channel mapping | LinkedIn campaigns map to `paid_social` by default; per-campaign overrides honored |

Files: full parallel tree under `app/services/ad_platforms/linkedin/`, `app/controllers/oauth/linkedin_ads_controller.rb`, view partials, routes, registry entry. Same testing rigour as Phase 2.

---

### Phase 4 — Per-connection metadata mapping

Sub-spec: `lib/specs/ad_platform_account_param_mapping_spec.md`

The pet-resort case: one mbuzz account, N physical locations, each location has its own Google + Meta + LinkedIn ad accounts. Conversions arrive with `properties: { location: "sydney" }` from the SDK. Tag each `AdPlatformConnection` with the same key/value so dashboards can group spend and revenue against the same axis.

**Storage.** New JSONB column `ad_platform_connections.metadata` (default `{}`). Distinct from `settings` (which holds OAuth/connection plumbing like `login_customer_id`); `metadata` is user-authored business attributes.

```ruby
metadata: {
  "location" => "sydney",
  "region"   => "nsw",
  "brand"    => "pet_resort_premium"
}
```

Open-ended schema — any string keys allowed, value must be a string. Validated as `is_a?(Hash)` with a 5KB size cap (smaller than the 50KB JSONB cap because metadata is small by design).

**Denormalization.** Add `ad_spend_records.metadata` JSONB. At sync time, the row parser merges `connection.metadata` onto each record. This is the trade — small write-time cost for fast dashboard filtering without joining back to `ad_platform_connections`.

**Backfill.** When `connection.metadata` changes, enqueue a job that updates all existing `ad_spend_records` for that connection (`UPDATE ad_spend_records SET metadata = ... WHERE ad_platform_connection_id = ?`). Atomic, no re-sync needed.

**Per-campaign overrides.** Extend the existing `connection.settings.campaign_overrides` pattern (already used for channel mapping per `google/campaign_channel_mapper.rb:18`):

```ruby
settings: {
  campaign_overrides: {
    "campaign_12345" => { metadata: { "location" => "melbourne" } }
  }
}
```

The row parser checks per-campaign overrides first, falls back to connection metadata. Already a clean extension point — no new architecture needed.

**UI.** New partial `app/views/accounts/integrations/_metadata_editor.html.erb`, rendered on each connection's detail page (`google_ads_account`, `meta_ads_account`, `linkedin_ads_account`). Stimulus-powered key/value list editor — add row, remove row, save. POST to a new `Accounts::IntegrationsController#update_metadata` action.

**Dashboard surfacing.** Out of scope for this branch — but the data is now available. Follow-up spec for "ROAS by location" dashboard widget once metadata is populated.

**Files:**

| File | Change |
|---|---|
| `db/migrate/...add_metadata_to_ad_platform_connections.rb` | NEW |
| `db/migrate/...add_metadata_to_ad_spend_records.rb` | NEW |
| `app/models/ad_platform_connection.rb` | Validate `metadata` is_a?(Hash), size < 5KB |
| `app/models/ad_spend_record.rb` | Validate `metadata` is_a?(Hash), size < 5KB |
| `app/services/ad_platforms/google/row_parser.rb` | Merge connection + campaign metadata |
| `app/services/ad_platforms/meta/row_parser.rb` | Same |
| `app/services/ad_platforms/linkedin/row_parser.rb` | Same |
| `app/jobs/ad_platforms/metadata_backfill_job.rb` | NEW — re-stamp records when connection metadata changes |
| `app/views/accounts/integrations/_metadata_editor.html.erb` | NEW |
| `app/javascript/controllers/metadata_editor_controller.js` | NEW — add/remove key-value rows |
| `app/controllers/accounts/integrations_controller.rb` | Add `#update_metadata` action |
| `config/routes.rb` | `patch :metadata, on: :member` (or equivalent) |

**Tests:**
- Model: validation, hash coercion, size limit, default empty.
- Row parser (per platform): connection-level metadata wins by default, per-campaign override wins when present, missing metadata yields `{}`.
- Backfill job: re-stamps existing records, scoped to the connection only, doesn't bleed across accounts.
- Controller: update-metadata happy path, validation errors, account isolation.
- View: Stimulus controller add/remove rows, form submission.

---

### Phase 5 — Production end-to-end test on pet-resort account

Sub-spec / findings doc: `lib/specs/ad_platform_meta_linkedin_test_findings.md`

No code (other than copy/follow-up fixes that fall out of testing).

**QA matrix on pet-resort production account:**

1. Enable `meta_ads_integration` and `linkedin_ads_integration` flags on the pet-resort account via rake task.
2. Connect Google Ads (already supported) for one location.
3. Connect Meta Ads for the same location.
4. Connect LinkedIn Ads for the same location.
5. Tag each connection with `metadata: { location: "<name>" }`.
6. Run a 30-day backfill on each.
7. Verify `AdSpendRecord` rows exist with correct `metadata`, currency, channel mapping.
8. Spot-check spend totals against each platform's native reporting UI (within 1% tolerance — known floating-point and timezone drift).
9. Verify ROAS dashboards still compute (Overview, Hourly, Device, Payback Period, Recommendations) without regression.
10. Verify cross-account isolation by spot-checking another paid account: it must not see pet-resort connections, spend rows, or metadata.
11. Disconnect a platform; verify the row stays at `disconnected` status, plan-limit count drops, future syncs skip it.
12. Re-authenticate flow: force a token expiry on one connection, click Re-authenticate, verify tokens refresh in place without creating a new row.
13. Repeat steps 2–7 for a second location to confirm metadata-driven roll-ups work.

**Copy updates that fall out:**
- `app/views/pages/pricing.html.erb` hero subtitle (currently says "Connect Google Ads, Meta, and LinkedIn ..." per `integration_plan_limits_spec.md:124` — verify accurate).
- `app/views/pages/pricing.html.erb` FAQ "Which ad platforms are supported?" — flip Meta/LinkedIn from "coming" to "live" if the prod test is clean.
- `app/views/accounts/integrations/show.html.erb` — when flag is enabled, swap Coming Soon cards for live Connect cards (Phase 1 already wires this).

**Findings doc structure:**
- One section per platform: green/red, surprises, follow-ups.
- A separate section for cross-cutting issues (e.g. timezone handling differs between Meta and Google).
- Action items: what to fix on this branch before merge, what to spin into a new spec.

**Exit criteria:** pet-resort account has Google + Meta + LinkedIn connected, all syncing daily, ROAS-by-location dashboard widget shows correct numbers in spot-checks, no cross-account leakage observed, all follow-ups either fixed on this branch or specced for future work.

---

## Definition of Done (umbrella)

- [ ] Phase 0 verification complete + recorded in `platform_api_approvals_spec.md`
- [ ] Phases 1–4 each shipped with passing tests, no AI attribution in commits, backdated per `feedback_commit_datetime.md`
- [ ] Phase 5 findings doc committed; all in-scope follow-ups fixed
- [ ] `bin/rails test` passes on this branch
- [ ] Spec moved to `lib/specs/old/` after `git flow feature finish`
- [ ] Pricing page copy reflects live platforms (if Phase 5 went green)

---

## Out of Scope

- TikTok adapter — deferred per `platform_api_approvals_spec.md:158`.
- Microsoft, Pinterest, Snapchat, Reddit, X, Apple Search Ads — coming-soon cards only.
- ROAS-by-location dashboard widget — separate spec once Phase 4 metadata is populated.
- Stripe / pricing changes — Phase 5 may flip copy from "coming" to "live" but does not change plan caps or prices.
- Backfilling Google Ads connections with metadata for accounts that already have Google connected — out of band; users can edit per the new UI when they're ready.
- Grandfathering accounts that hit the per-plan integration cap when Meta/LinkedIn enable for them — already covered as Out of Scope in `integration_plan_limits_spec.md:191`.

---

## Open Questions

1. **Meta access tier.** Standard or Advanced `ads_read`? Phase 0 must answer. If only Standard, document the production rate-limit risk and either gate the flag to one-off pilot accounts or block Phase 5 on Advanced approval.
2. **LinkedIn approval.** Confirm Development tier is approved (was submitted 5 Mar 2026, review window 2–4 weeks, so should be in by now).
3. **Metadata key conventions.** Free-form strings, or do we want to register known keys (`location`, `region`, `brand`) somewhere for autocomplete in the editor UI? Probably free-form with a "common keys" hint list — decide in Phase 4 sub-spec.
4. **Conversion-side mapping.** Conversions store `properties` JSONB today. Confirm the property key the pet-resort SDK uses (`location` vs `store_id` vs `branch_id`) so the dashboard widget down the line can join correctly. Pin this in the Phase 5 findings doc.
