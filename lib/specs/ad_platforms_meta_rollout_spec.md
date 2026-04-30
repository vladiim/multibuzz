# Ad Platforms — Meta Rollout (umbrella)

**Date:** 2026-04-30 (re-shaped from `ad_platforms_meta_linkedin_rollout_spec.md`)
**Priority:** P1
**Status:** Phases 0–2 ✅ complete · Phase 3 in flight · Phases 4–5 pending
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
| 3 — Metadata mapping: finish + UAT | (was 4) | 🟡 In flight | inline below |
| 4 — Apply metadata UX to Google + lock pattern | NEW | ⏳ Pending | inline below |
| 5 — Pet-resort production E2E test | (was 5) | ⏳ Pending | `lib/specs/ad_platform_meta_test_findings.md` (created on completion) |

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
- ❌ Edit-after-connect UI on the per-connection detail page
- ❌ `Accounts::IntegrationsController#update_metadata` action + route

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

- [ ] **3.3.1** RED test: PATCH with valid metadata → connection updates, backfill enqueued, redirect 302. Cross-account isolation. Validation errors render flash.
- [ ] **3.3.2** GREEN: action + route (`patch :metadata, on: :member` or analog).
- [ ] **3.3.3** Detail-path resolution helper — small concern or method on `AdPlatformConnection` returning the right named route per platform.

### 3.4 — `_metadata_editor.html.erb` (Stimulus)

Form partial rendered on each connection detail page (`google_ads_account.html.erb`, `meta_ads_account.html.erb`). Shows current key/value, allows edit, posts to `update_metadata`.

- [ ] **3.4.1** Partial with form posting to the new route
- [ ] **3.4.2** Stimulus controller `metadata_editor_controller.js` — single key/value for now (matches `MetadataLinkCheck` single-pair assumption); add-row UI is a follow-up
- [ ] **3.4.3** Wire into both `google_ads_account.html.erb` and `meta_ads_account.html.erb`

### 3.5 — UAT on a dev account

Manual matrix on a dev account with `meta_ads_integration` flag enabled:

1. Connect Google Ads → tag with `{ location: "test-loc-1" }` at connect time → verify `ad_platform_connections.metadata` and at least one `ad_spend_records.metadata` row
2. Connect Meta Ads → same
3. Visit detail page for each → confirm `_metadata_panel.html.erb` shows correct linked/unlinked state
4. Edit metadata via `_metadata_editor.html.erb` → confirm row updates, backfill job enqueues, all spend records re-stamp
5. Send a test conversion via SDK with `properties: { location: "test-loc-1" }` → confirm panel flips from `:unlinked` to `:linked`
6. Cross-account check: visit a second dev account, confirm no leakage
7. Edge cases: empty metadata, 5KB-cap, non-hash → controller validation errors, no orphan jobs

### 3.6 — Definition of Done (Phase 3)

- [ ] All 3.1–3.4 sub-tasks committed with passing tests
- [ ] UAT matrix run against a dev account; findings noted inline in this section
- [ ] No mocks added (per `feedback_no_mocks.md`)
- [ ] No new helper clusters in controllers (per `feedback_thin_controllers.md`)

---

## Phase 4 — Apply metadata UX to Google + lock pattern ⏳

**Goal:** confirm Google works identically to Meta after Phase 3, formalize the pattern so any future adapter (LinkedIn, TikTok, Microsoft, …) inherits it for free, no platform-specific surprises.

### 4.1 — Audit Google end-to-end

Walk the same Phase 3.5 UAT matrix against a Google connection on the same dev account. Phase 3 deliverables (edit UI, backfill, panel) are platform-agnostic — they should "just work." Document any gap:

- [ ] **4.1.1** Google connect-time picker exposes `KnownMetadata` keys (already shipped — verify)
- [ ] **4.1.2** `Google::AcceptConnectionService` persists `metadata` (already shipped — verify)
- [ ] **4.1.3** `Google::RowParser` merges `connection.metadata` onto rows (already shipped — verify)
- [ ] **4.1.4** Edit UI + backfill job work on Google connections (built in Phase 3 — verify)
- [ ] **4.1.5** Per-campaign metadata override via `connection.settings.campaign_overrides` — confirm parser honors per-campaign metadata if/when populated (defer building UI)

### 4.2 — Lock the pattern

- [ ] **4.2.1** `lib/specs/ad_platform_adapter_template_spec.md` Phase 4 already documents the metadata contract. Cross-check it matches what Phase 3 actually shipped — patch any drift.
- [ ] **4.2.2** `lib/specs/GUIDE.md` "Ad Platform Adapter Lifecycle Checklist" already references the connect-time metadata + RowParser merge. Cross-check.
- [ ] **4.2.3** Note in template's "Common Pitfalls" any new gotchas surfaced in Phase 3 (e.g. backfill-job race conditions, single-key vs multi-key metadata).

### 4.3 — Quick scan for missed adapters

Today only Google + Meta are live; no other adapters exist on this branch. Sanity-grep `app/services/ad_platforms/` for any platform-specific service that mutates `connection.metadata` directly — there shouldn't be any; all writes go through `AcceptConnectionService(metadata:)` or `Accounts::IntegrationsController#update_metadata`.

### 4.4 — Definition of Done (Phase 4)

- [ ] Google UAT matrix passes with same outcome as Meta
- [ ] Template spec + GUIDE.md confirmed in sync with shipped code
- [ ] Zero per-adapter metadata writes outside the shared services

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

- [ ] Phases 0–4 complete with passing tests
- [ ] Phase 5 findings doc committed; in-scope follow-ups fixed
- [ ] `bin/rails test` passes on this branch
- [ ] Spec moved to `lib/specs/old/ad_platforms_meta_rollout_spec.md` after `git flow feature finish`
- [ ] Pricing page copy reflects live Meta if Phase 5 went green
- [ ] LinkedIn deferred spec lives at `lib/specs/future/ad_platform_linkedin_integration_spec.md` for the next branch to pick up

---

## Out of Scope

- **LinkedIn adapter.** Deferred to `lib/specs/future/ad_platform_linkedin_integration_spec.md`. To be picked up on a fresh branch following the standard template spec — same shape as Meta.
- **TikTok / Microsoft / Pinterest / Snapchat / Reddit / X / Apple Search Ads.** Coming-soon cards only. Each future adapter follows `ad_platform_adapter_template_spec.md`.
- **ROAS-by-location dashboard widget.** Separate spec once Phase 4 metadata is populated in prod.
- **Stripe / pricing changes.** Phase 5 may flip copy from "coming" to "live"; does not change plan caps or prices.
- **Backfilling Google Ads connections with metadata for accounts that already have Google connected.** Out of band; users edit via the Phase 3 UI when ready.
- **Grandfathering accounts that hit the per-plan integration cap when Meta enables for them.** Already covered in `integration_plan_limits_spec.md:191`.
- **Multi-key metadata UI.** Phase 3 ships a single key/value editor (matching `MetadataLinkCheck`'s single-pair assumption). Multi-row editor is a follow-up if a customer needs `{ location:, brand:, region: }` simultaneously.

---

## Open Questions

1. **Meta access tier.** Standard or Advanced `ads_read`? At Standard ("Ready for testing") rate limits are tight. Phase 5 will surface whether we hit ceilings on a real 30-day backfill — if yes, gate the flag to one-off pilot accounts and apply for Advanced before broader rollout.
2. **Conversion-side mapping.** Conversions store `properties` JSONB today. The pet-resort SDK uses `location` as the property key (confirmed in 1Password notes). Pin in Phase 5 findings doc — or update if it diverges from `location`.
3. **VCR record-vs-block-net.** `WebMock.disable_net_connect!(allow_localhost: true)` is in `test_helper.rb`. Phase 5 cassette-recording uses `VCR_RECORD_MODE=new_episodes` env var; confirm CI defaults to `:none` so accidental recording can't happen in pipeline.
