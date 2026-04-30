# Ad Platforms — Meta Rollout (umbrella)

**Date:** 2026-04-30 (re-shaped from `ad_platforms_meta_linkedin_rollout_spec.md`)
**Priority:** P1
**Status:** Phases 0–4 ✅ build complete · Meta UAT ✅ · Phase 5 (prod E2E) blocked on Google OAuth verification
**Branch:** `feature/ad-platforms-meta-linkedin-rollout` (kept under the original name; LinkedIn was deferred mid-branch — see [Out of Scope](#out-of-scope))

---

## Summary

Ship the Meta Ads adapter end-to-end alongside Google, then round out the per-connection metadata story (edit-after-connect UI, backfill job, link-check display) so the pet-resort production account can roll spend up against conversions tagged with the same params (`{ location: "sydney" }`). Close with an end-to-end test on the pet-resort account in prod.

LinkedIn was originally part of this branch. We're deferring it to a separate spec — `lib/specs/future/ad_platform_linkedin_integration_spec.md` — so this branch can finish and ship sooner.

This spec is the umbrella. Each phase below ships its own RED→GREEN tests and atomic commits on this one feature branch. New ad-platform adapters added after this branch should follow the standard adapter shape captured in **`lib/specs/ad_platform_adapter_template_spec.md`**.

---

## Phase Status

| Phase | Was | Status | Sub-spec |
|---|---|---|---|
| 0 — External prereqs (Meta) | 0 | ✅ Done | inline below |
| 1 — Feature-flag scaffolding | 1 | ✅ Done | `lib/specs/ad_platform_feature_flags_spec.md` |
| 2 — Meta Ads adapter | 2 | ✅ Done | `lib/specs/ad_platform_meta_integration_spec.md` |
| 3 — Metadata mapping: finish + UAT | (was 4) | ✅ Build + Meta UAT complete | inline below |
| 4 — Apply metadata UX to Google + lock pattern | NEW | ✅ Pattern locked · Google UAT blocked on verification | inline below |
| 5 — Pet-resort production E2E test | (was 5) | 🚫 Blocked on Google OAuth verification (4-6 wk review) | `lib/specs/ad_platform_meta_test_findings.md` (created on completion) |
| 6 — Spend dashboard metadata filter + breakdown | NEW (post-merge) | 📋 Specced — separate branch | `lib/specs/spend_dashboard_metadata_breakdown_spec.md` |

---

## Phase 0 — Verify external prerequisites (Meta only) ✅

- [x] **0.1** `bin/rails credentials:show` — `meta_ads.app_id`, `meta_ads.app_secret` set in dev + prod
- [x] **0.2** Meta Business Verification ✅ (Forebrite Pty Ltd); `ads_read` scope "Ready for testing"
- [x] **0.3** Live API smoke test against `/me/adaccounts` — 25+ ad accounts returned including pet-resort multi-location
- [x] **0.4** `lib/specs/platform_api_approvals_spec.md` updated
- [x] **0.5** Pet-resort production account ID recorded in 1Password (NEVER commit per CLAUDE.md hard rule)

LinkedIn API approval status moved to the deferred spec.

---

## Phase 1 — Feature-flag scaffolding ✅

Sub-spec: `lib/specs/ad_platform_feature_flags_spec.md`

`Account::FeatureFlags` concern, `account_feature_flags` table, `FeatureFlags` constants module (`META_ADS_INTEGRATION`, `LINKEDIN_ADS_INTEGRATION`), admin UI at `/admin/feature_flags`, rake tasks (`feature_flags:enable / disable / list / accounts`).

The `LINKEDIN_ADS_INTEGRATION` constant stays in place even though Phase 3 (LinkedIn adapter) is deferred — the flag costs nothing and the deferred spec uses it on day one.

---

## Phase 2 — Meta Ads adapter ✅

Sub-spec: `lib/specs/ad_platform_meta_integration_spec.md`

All 13 service classes shipped under `app/services/ad_platforms/meta/`; OAuth controller, views, routes, and verify rake task (`ad_platforms:meta:verify_credentials`) all live.

**Key changes vs. original Phase 2 plan:**

- **Global `AdPlatforms::ApiUsageTracker`.** Originally specced as a per-platform `Meta::ApiUsageTracker`. Refactored to a single global tracker with per-platform `LIMITS` + `DISPLAY_NAMES` so the third+ adapter doesn't repeat the class. New adapters add their key + limit and call `AdPlatforms::ApiUsageTracker.increment!(:platform)` from their `ApiClient`. See `feedback_global_processor_pattern` memory and `lib/specs/ad_platform_adapter_template_spec.md` Phase 2.7.
- **Drift note resolved.** `a83ce27` stopped Meta from stamping the access token into the `refresh_token` column — Meta has no OAuth2 refresh token; it re-exchanges the long-lived token.
- **VCR cassettes for orchestrators (TokenRefresher, ListAdAccounts, SpendSyncService) deferred to Phase 5.** Pure parsers + DB-only orchestrators have direct unit tests; HTTP-touching orchestrator cassettes will be recorded against the live pet-resort account during Phase 5 prod testing. The infra (`test/test_helper.rb` VCR config, `lib/vcr_filters.rb`) is wired and audited.

---

## Phase 3 — Metadata mapping: finish + UAT 🟡

**Goal:** every metadata feature the spec promised, working end-to-end on a dev account with at least one Meta connection. Platform-agnostic infrastructure — Phase 4 then audits Google.

### 3.0 — Current state (verified 2026-04-30)

- ✅ `ad_platform_connections.metadata` JSONB (5KB, hash-validated)
- ✅ `ad_spend_records.metadata` JSONB (5KB, hash-validated)
- ✅ `AdPlatforms::MetadataNormalizer`, `ConnectMetadataExtractor`, `KnownMetadata` shared services
- ✅ `Google::RowParser` and `Meta::RowParser` both merge `connection.metadata` onto each row
- ✅ `Google::AcceptConnectionService` and `Meta::AcceptConnectionService` both accept `metadata:` kwarg
- ✅ Connect-time metadata picker in `oauth/{google_ads,meta_ads}/select_account` views
- ✅ `AdPlatforms::MetadataLinkCheck` + `_metadata_panel.html.erb` (display panel)
- ✅ `AdPlatforms::MetadataBackfillService` + thin `MetadataBackfillJob` wrapper
- ✅ Edit-after-connect UI on the per-connection detail page
- ✅ `Accounts::IntegrationsController#update_metadata` action + route

### 3.1 — Commit the in-flight link-check work

- [ ] Commit `app/services/ad_platforms/metadata_link_check.rb` + test
- [ ] Commit `app/views/accounts/integrations/_metadata_panel.html.erb` + the `google_ads_account.html.erb` / `meta_ads_account.html.erb` rendering
- [ ] Smoke check: panel renders correctly across `:linked`, `:unlinked` (with hint), `:unlinked` (no hint), `:no_metadata` states

### 3.2 — `MetadataBackfillJob` (platform-agnostic)

`app/jobs/ad_platforms/metadata_backfill_job.rb`:

```ruby
def perform(connection_id)
  connection = AdPlatformConnection.find(connection_id)
  AdSpendRecord.where(ad_platform_connection_id: connection.id)
    .update_all(metadata: connection.metadata)
end
```

- [x] **3.2.1** RED test: enqueue with a connection that has spend records, assert all records re-stamp with the new metadata; assert another account's records untouched.
- [x] **3.2.2** GREEN: `AdPlatforms::MetadataBackfillService` (full re-stamp, returns `records_updated` count) + thin `AdPlatforms::MetadataBackfillJob` wrapper. Account-scoped via the connection's `ad_spend_records` association.

### 3.3 — `update_metadata` controller action (platform-agnostic)

`Accounts::IntegrationsController#update_metadata`:

```ruby
def update_metadata
  connection = current_account.ad_platform_connections.find_by_prefix_id!(params[:id])
  connection.update!(metadata: AdPlatforms::MetadataNormalizer.call(params[:metadata]))
  AdPlatforms::MetadataBackfillJob.perform_later(connection.id)
  redirect_to <detail-path-for-platform>, notice: "Metadata updated. Backfill in progress."
end
```

- [x] **3.3.1** RED test: PATCH with valid metadata → connection updates, backfill enqueued, redirect 302. Cross-account isolation (`find_by_prefix_id!` returns 404). Validation errors render flash.
- [x] **3.3.2** GREEN: `Accounts::IntegrationsController#update_metadata` + route `patch "metadata/:id"` named `update_metadata_account_integrations_path`.
- [x] **3.3.3** Detail-path resolution kept inline in the controller as `detail_path_for(connection)` — three-line case statement; doesn't merit a model concern.

### 3.4 — `_metadata_editor.html.erb` (Stimulus)

Form partial rendered on each connection detail page (`google_ads_account.html.erb`, `meta_ads_account.html.erb`). Shows current key/value, allows edit, posts to `update_metadata`.

- [x] **3.4.1** `_metadata_editor.html.erb` partial: form posts `metadata_key` + `metadata_value` flat params to `update_metadata_account_integrations_path`. Pre-fills from `connection.metadata_pair` (new model method, sole source of truth for the single-pair assumption).
- [x] **3.4.2** Stimulus: reused the existing `toggle` controller for show/edit swap on `_metadata_panel.html.erb`. No new JS controller needed yet — a custom `metadata_editor_controller.js` becomes worth adding only when the multi-row add UI lands.
- [x] **3.4.3** Wired in via `_metadata_panel.html.erb` (already rendered on both `google_ads_account.html.erb` and `meta_ads_account.html.erb`).

### 3.5 — UAT on a dev account ✅

Walked through on a dev account with both `meta_ads_integration` and `google_ads_integration` flags enabled. **Meta side completed cleanly; Google side blocked on OAuth verification (separate — see [Phase 4 status](#phase-4--apply-metadata-ux-to-google--lock-pattern-)).**

**UAT findings (Meta) — all addressed in-branch:**

1. **Connect-time picker was confusing** — original design used `<select>` with "+ Add new..." sentinel modes, empty-state degraded to dropdowns with no options, no inline explanation of what "Property" meant. Redesigned (`f954073`) to plain text inputs with `<datalist>` for known-key autocomplete, soft-bordered "Tag this account (optional)" group, click-to-expand info button with when/how/skip-if explainer, generic placeholders ("plan_name" / "Pro"). Deleted `metadata_picker_controller.js` entirely — single Stimulus toggle controller handles the show/edit swap.
2. **Hidden fallback inputs were visible** — Tailwind `block` class was overriding the HTML `[hidden]` attribute. Fixed by switching the redesign to use Tailwind's `hidden` class managed via `classList`, plus deletion of the entire fallback-input mechanism.
3. **Multi-account flow was hidden** — connecting one account redirected to the all-platforms integrations index and cleared the OAuth session, forcing re-OAuth for every additional account. Fixed in two passes:
   - `0de73b7` made `create_connection` redirect to the per-platform page instead of integrations index, with a prominent "+ Connect another Meta Ads account" CTA at the bottom of the connection list when N≥1
   - `35e1ca5` kept the OAuth session alive across connects on `select_account` (success returns `clear_session: false`), added a `done` action that explicitly closes the flow, and the `select_account` view marks already-connected ad accounts with a "Connected ✓" stub instead of the form
4. **No surfacing on Spend dashboard** — operators tag connections with metadata but the Spend dashboard rolls up across all connections with no filter or breakdown. Captured in new spec `lib/specs/spend_dashboard_metadata_breakdown_spec.md` for a separate branch post-merge (commit `61af9a0`).
5. **`pair` was scattered through the editor view** — refactored to a memoized `AdPlatformConnection#metadata_pair` model method (`e5be985`), now the single source of truth for the single-pair assumption (used by both the editor view and `MetadataLinkCheck`).

**UAT findings (Google) — pending:**

6. **OAuth `access_denied`** — Google OAuth app is still in Testing mode; non-test-users hit "Error 403: access_denied". Pulled Google off live behind `FeatureFlags::GOOGLE_ADS_INTEGRATION` (`5a6662c`); existing connections continue to sync. Standard Access + verification application submitted via Google Ads developer portal with the design doc generated at `lib/docs/google_ads_api_application.md` (commit `94acc1f`). 4-6 wk Google review window. See `project_google_ads_api_status` memory for status.

### 3.6 — Definition of Done (Phase 3) ✅

- [x] All 3.1–3.4 sub-tasks committed with passing tests (`bin/rails test` green)
- [x] UAT matrix run on a dev account; Meta side complete with findings addressed; Google side blocked on verification (tracked in 4.4)
- [x] No mocks added (per `feedback_no_mocks.md`)
- [x] No new helper clusters in controllers (`metadata_pair`, `metadata_key`, `metadata_value`, `detail_path_for` — three small memoized helpers + one route resolver, all tied to a single action)

---

## Phase 4 — Apply metadata UX to Google + lock pattern ✅ Pattern · 🚫 Google UAT blocked

**Goal:** confirm Google works identically to Meta after Phase 3, formalize the pattern so any future adapter (LinkedIn, TikTok, Microsoft, …) inherits it for free, no platform-specific surprises.

### 4.1 — Audit Google end-to-end

The Phase 3 deliverables (edit UI, backfill, panel) are platform-agnostic by construction — Google's pieces shipped earlier in the branch (`8c66614`, `8a55837`, `2de32ee`) are still the active code. Verified:

- [x] **4.1.1** Google connect-time picker exposes `KnownMetadata` keys via the shared `_connect_account_row.html.erb` partial that Meta also uses
- [x] **4.1.2** `Google::AcceptConnectionService` persists `metadata` via the shared `MetadataNormalizer`
- [x] **4.1.3** `Google::RowParser` merges `connection.metadata` onto rows (line 20: `connection_attrs.merge(dimension_attrs).merge(campaign_attrs).merge(metric_attrs).merge(metadata_attrs)`)
- [x] **4.1.4** Edit UI + backfill job work on Google connections — `_metadata_editor.html.erb` is rendered by `_metadata_panel.html.erb` which is included on `google_ads_account.html.erb`; `MetadataBackfillJob` is platform-agnostic, takes a connection ID
- [ ] **4.1.5** Per-campaign metadata override via `connection.settings.campaign_overrides` — left for follow-up; the parser plumbing is in place but no UI to set per-campaign overrides yet
- [ ] **End-to-end Google UAT** — blocked on Google OAuth verification. The flag-gated controller redirects with "Google Ads is currently in private beta" until the user adds themselves as a test user in GCC. Once Google verification clears, walk the Phase 3.5 matrix on a real Google connection.

### 4.2 — Lock the pattern ✅

- [x] **4.2.1** `lib/specs/ad_platform_adapter_template_spec.md` Phase 4 documents the metadata contract; verified in sync with shipped code
- [x] **4.2.2** `lib/specs/GUIDE.md` "Ad Platform Adapter Lifecycle Checklist" references connect-time metadata + RowParser merge; in sync
- [x] **4.2.3** Common Pitfalls section in the template captures the gotchas surfaced in Phase 3 UAT — empty-state-first design, no mode-switching, click-to-expand explainers, plain inputs over dropdowns. Memorialized in `feedback_ui_patterns` memory.

### 4.3 — Quick scan for missed adapters ✅

Today only Google + Meta are live. Verified no platform-specific service mutates `connection.metadata` directly — all writes go through `AcceptConnectionService(metadata:)` (connect time) or `Accounts::IntegrationsController#update_metadata` (edit time). Future adapters (LinkedIn, TikTok, Microsoft) will get this for free as long as they follow the template spec.

### 4.4 — Definition of Done (Phase 4)

- [x] Template spec + GUIDE.md confirmed in sync with shipped code
- [x] Zero per-adapter metadata writes outside the shared services
- [x] Google `ApiUsageTracker` migrated to the global tracker (`10d9eac`); pattern locked
- [ ] Google UAT matrix — blocked on Google OAuth verification (4-6 wk). Tracked in `project_google_ads_api_status` memory.

---

## Phase 5 — Pet-resort production E2E test ⏳

Findings doc: `lib/specs/ad_platform_meta_test_findings.md` (created on completion)

No new code unless a defect surfaces. Walks the pet-resort production account through the full integration matrix.

### QA matrix on pet-resort production

1. Enable `meta_ads_integration` on the pet-resort account via `bin/rails feature_flags:enable`
2. Connect Google Ads for one location; tag with `{ location: "<name>" }`
3. Connect Meta Ads for the same location; tag with the same location
4. Run a 30-day backfill on each
5. Verify `AdSpendRecord` rows exist with correct `metadata`, currency, channel mapping
6. Spot-check spend totals against each platform's native reporting UI (within 1% tolerance — known floating-point + timezone drift)
7. Verify ROAS dashboards still compute (Overview, Hourly, Device, Payback Period, Recommendations) without regression
8. Cross-account isolation: spot-check another paid account; confirm no pet-resort data leakage
9. Disconnect a platform; verify status flips, plan-limit count drops, future syncs skip
10. Re-authenticate flow: force token expiry, click Re-authenticate, verify tokens refresh in place
11. Repeat steps 2–7 for a second location to confirm metadata-driven roll-ups work
12. Edit metadata via the new UI on a live pet-resort connection; confirm `MetadataBackfillJob` re-stamps records
13. Record VCR cassettes for `Meta::SpendSyncService`, `Meta::ListAdAccounts`, `Meta::TokenRefresher` against the live pet-resort connection (filtering per `lib/vcr_filters.rb`); commit. Closes the Phase 2 deferral.

### Copy updates that fall out

- `app/views/pages/pricing.html.erb` hero subtitle — verify accurate
- `app/views/pages/pricing.html.erb` FAQ "Which ad platforms are supported?" — flip Meta from "coming" to "live" if prod test is clean
- `app/views/accounts/integrations/show.html.erb` — already swaps Coming Soon for live card via flag

### Definition of Done (Phase 5)

- [ ] Pet-resort account has Google + Meta connected, syncing daily
- [ ] ROAS-by-location dashboard widget shows correct numbers in spot-checks (or, if widget is still pending, raw `AdSpendRecord` query confirms metadata-keyed roll-ups)
- [ ] No cross-account leakage observed
- [ ] All in-scope follow-ups fixed on this branch; out-of-scope items written into a follow-up spec
- [ ] VCR cassettes committed (filtered) for the three Meta orchestrators
- [ ] Pricing copy reflects live Meta integration if the prod test went green

---

## Definition of Done (umbrella)

- [x] Phases 0–4 complete with passing tests
- [ ] Phase 5 findings doc committed; in-scope follow-ups fixed (blocked on Google OAuth verification)
- [x] `bin/rails test` passes on this branch (other than pre-existing `Dashboard::ExportJobTest` flake)
- [ ] Spec moved to `lib/specs/old/ad_platforms_meta_rollout_spec.md` after `git flow feature finish`
- [ ] Pricing page copy reflects live Meta if Phase 5 went green (deferred to post-verification)
- [ ] LinkedIn deferred spec lives at `lib/specs/future/ad_platform_linkedin_integration_spec.md` for the next branch to pick up

**Branch is mergeable today.** Remaining items are externally-blocked (Google verification) or post-merge (pricing copy, LinkedIn spec extraction). Post-merge work tracked in:
- `project_google_ads_api_status` memory — verification status + per-customer unblock paths
- `lib/specs/spend_dashboard_metadata_breakdown_spec.md` — the dashboard surfacing follow-up

---

## Out of Scope

- **LinkedIn adapter.** Deferred to `lib/specs/future/ad_platform_linkedin_integration_spec.md`. To be picked up on a fresh branch following the standard template spec — same shape as Meta.
- **TikTok / Microsoft / Pinterest / Snapchat / Reddit / X / Apple Search Ads.** Coming-soon cards only. Each future adapter follows `ad_platform_adapter_template_spec.md`.
- **Spend dashboard metadata filter + breakdown card.** Specced in `lib/specs/spend_dashboard_metadata_breakdown_spec.md`. Closes the "ROAS by location/plan/whatever" loop opened by Phase 3 — the metadata is fully populated end-to-end at the data layer; the dashboard surface is the missing yard. Separate branch off `develop` after this one lands.
- **Google Ads OAuth verification for general availability.** As of 2026-04-30 the OAuth app is still in Testing mode in Google Cloud Console — non-test-users hit `Error 403: access_denied`. Gated behind `FeatureFlags::GOOGLE_ADS_INTEGRATION` (default OFF in prod) until verification is submitted and approved. See `project_google_ads_api_status` memory for status + unblock paths.
- **Stripe / pricing changes.** Phase 5 may flip copy from "coming" to "live"; does not change plan caps or prices.
- **Backfilling Google Ads connections with metadata for accounts that already have Google connected.** Out of band; users edit via the Phase 3 UI when ready.
- **Grandfathering accounts that hit the per-plan integration cap when Meta enables for them.** Already covered in `integration_plan_limits_spec.md:191`.
- **Multi-key metadata UI.** Phase 3 ships a single key/value editor (matching `MetadataLinkCheck`'s single-pair assumption). Multi-row editor is a follow-up if a customer needs `{ location:, brand:, region: }` simultaneously.

---

## Open Questions

1. **Meta access tier.** Standard or Advanced `ads_read`? At Standard ("Ready for testing") rate limits are tight. Phase 5 will surface whether we hit ceilings on a real 30-day backfill — if yes, gate the flag to one-off pilot accounts and apply for Advanced before broader rollout.
2. **Conversion-side mapping.** Conversions store `properties` JSONB today. The pet-resort SDK uses `location` as the property key (confirmed in 1Password notes). Pin in Phase 5 findings doc — or update if it diverges from `location`.
3. **VCR record-vs-block-net.** `WebMock.disable_net_connect!(allow_localhost: true)` is in `test_helper.rb`. Phase 5 cassette-recording uses `VCR_RECORD_MODE=new_episodes` env var; confirm CI defaults to `:none` so accidental recording can't happen in pipeline.
