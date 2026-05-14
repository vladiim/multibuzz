# Google Ads — General Availability Rollout

**Date:** 2026-05-15
**Priority:** P1
**Status:** Phases 1-3 code complete ✅ · Phase 0 (incognito verify) + Phase 2 prod run + Phase 4 archive pending
**Branch:** `feat/conversion-feedback` (bundled into in-flight branch per user request)

---

## Summary

Take Google Ads out of private beta and open it to every paid account, read-only. The adapter has been live since March; the OAuth consent screen was published to External / In production on 15 May 2026. Three things still gate general availability: an incognito confirmation that the unverified-app warning is gone, a hardcoded `Rails.env.production?` check on the integrations page that always hides the live card in prod, and a flag-enable pass across paid accounts. This spec closes those. Conversion push (offline conversion imports) stays out of scope and ships as a separate opt-in feature later, tracked in `lib/specs/future/google_ads_conversion_push_spec.md`.

This rollout also unblocks Phase 5 of `ad_platforms_meta_rollout_spec.md` (pet-resort production E2E test), which has been waiting on Google verification.

---

## Current State

### What's live

- ✅ Google Ads adapter end-to-end: `app/services/ad_platforms/google/` (TokenExchanger, ListCustomers, AcceptConnectionService, SpendSyncService, RowParser, ApiClient with global usage tracker)
- ✅ OAuth controller: `app/controllers/oauth/google_ads_controller.rb` with `skip_marketing_analytics`, `require_feature_flag` (`FeatureFlags::GOOGLE_ADS_INTEGRATION`), `require_paid_plan`, `require_connection_slot`
- ✅ Routes: `oauth/google_ads/*` and `account/integrations/google_ads(/:id)`
- ✅ Connection detail views with metadata editor + link-check panel
- ✅ Feature flag scaffolding: `FeatureFlags::GOOGLE_ADS_INTEGRATION` constant, `Account#feature_enabled?`, rake tasks (`feature_flags:enable/disable/list/accounts`)
- ✅ Developer token: Basic Access (15k ops/day)
- ✅ OAuth consent screen: published "In production" / External on 15 May 2026

### What's blocking GA

| # | Gap | File | Today | Target |
|---|---|---|---|---|
| 1 | Unverified-app warning not confirmed cleared | n/a (Google Cloud Console) | Status reads "In production" but unverified-warning interstitial may still appear | Incognito test against a non-test-user account shows no warning |
| 2 | View card hides live integration in production | `app/views/accounts/integrations/show.html.erb:26` | `if Rails.env.production?` shows Coming Soon, else live card | Use `FeatureFlags::GOOGLE_ADS_INTEGRATION` like Meta does at line 34 |
| 3 | Feature flag is OFF by default for all accounts | `account_feature_flags` table | Only accounts with explicit row see the live card | Bulk-enabled for all paid accounts (mirrors how Meta rollout would have shipped) |
| 4 | Stale memory note | `~/.claude/projects/.../project_google_ads_api_status.md` | Claims view was un-hardcoded 2026-05-05 | Update after Phase 1 lands |

### Data Flow (no change)

```
OAuth connect → TokenExchanger → ListCustomers → AcceptConnectionService
   → AdPlatformConnection (account_id, platform: google_ads, metadata jsonb)
SpendSyncService (daily) → googleAds:search → RowParser → ad_spend_records
   (merged with connection.metadata)
```

The data path doesn't change. This rollout only changes who can see the connect entry point.

---

## Proposed Solution

Four phases, ordered by reversibility (low-risk before high-risk):

1. **Phase 0** — Incognito verification of OAuth consent screen (no code).
2. **Phase 1** — Replace `Rails.env.production?` with the flag check on the integrations page. Smoke test on dev with the flag toggled on/off.
3. **Phase 2** — Bulk-enable `GOOGLE_ADS_INTEGRATION` for all paid accounts via a one-off rake task. Idempotent. Logs what it enabled.
4. **Phase 3** — Update pricing/marketing copy where Google Ads is still hedged as "coming" or "private beta". Verify pricing page doesn't lie about plan caps.

After this, Phase 5 of the Meta rollout (`ad_platforms_meta_rollout_spec.md`) is unblocked and the pet-resort production E2E test can run on Google + Meta together.

### Key Files

| File | Purpose | Change |
|---|---|---|
| `app/views/accounts/integrations/show.html.erb` | Integrations list | Swap `Rails.env.production?` for `current_account.feature_enabled?(FeatureFlags::GOOGLE_ADS_INTEGRATION)` (Phase 1) |
| `lib/tasks/google_ads_rollout.rake` | One-off bulk enable | New file: rake task that enables the flag for every paid account, logs each, idempotent (Phase 2) |
| `app/views/pages/pricing.html.erb` | Marketing copy | Verify "Google Ads is live today" claim is accurate after Phase 1 ships; tweak hero subtitle line 41 if needed (Phase 3) |
| `app/views/accounts/integrations/_coming_soon_card.html.erb` | Coming-soon card | No code change, but verify partial isn't rendered for Google in any path (Phase 1 verification) |
| `lib/specs/ad_platforms_meta_rollout_spec.md` | Cross-spec link | Update Phase 5 status note: "Unblocked — see google_ads_rollout_spec.md" (Phase 3) |
| `lib/specs/platform_api_approvals_spec.md` | Approvals tracker | Update Google status after Phase 0 incognito confirmation (Phase 0) |

---

## All States

| State | Condition | Expected Behavior |
|---|---|---|
| Paid account, flag ON | After Phase 2 | Sees live "Google Ads" card on `/account/integrations`, can click Connect, OAuth flow runs, no unverified-app warning |
| Paid account, flag OFF (legacy / new signup before backfill catches up) | After Phase 1, before Phase 2 ran for this account | Sees Coming Soon card with notify-me. After Phase 2 task runs, sees live card on next page load. |
| Free / trial account | Always | Sees Coming Soon card. Connect attempt redirected by `require_paid_plan` guard with upgrade modal. |
| Account at connection cap | Already has 1 paid connection on Free Plan equivalent | Connect attempt redirected by `require_connection_slot` with limit alert. No change. |
| Unverified-app warning still present (Phase 0 fails) | Google verification not actually complete | Abort rollout. Re-engage Google verification; do not flip view gate. |
| New signup post-rollout | Account created after Phase 2 task ran | Default-OFF flag stays default-OFF for new accounts unless we add to a per-plan default. **Out of scope decision** — see [Open Questions](#open-questions). |

---

## Implementation Tasks

### Phase 0 — Confirm OAuth verification is actually live (no code)

- [ ] **0.1** Open an incognito window. Use a Google account that is **not** on the GCC Test users list. Hit `https://mbuzz.co/oauth/google_ads/connect` (after temporarily enabling the flag on a dev/staging account for this test).
- [ ] **0.2** Walk the consent screen. Confirm there is no "Google hasn't verified this app" yellow interstitial.
- [ ] **0.3** Check `hello@mbuzz.co` (inbox + spam) for `oauth-verification@google.com` confirmation email. Save to 1Password if present.
- [ ] **0.4** If no warning + flow completes: ✅ proceed to Phase 1. Update `project_google_ads_api_status` memory to reflect verified.
- [ ] **0.5** If warning still appears: abort rollout. Investigate whether app is published-but-unverified vs verified. The "In production" status alone does not guarantee verification cleared for sensitive scopes.

### Phase 1 — Flip the integrations page gate (RED → GREEN) ✅

Status: shipped 2026-05-15 in commit `2d131a9`. All 3925 tests pass. Manual smoke (1.4) still on user. Flag is OFF by default in prod so the view will show Coming Soon until Phase 2 enables.

- [x] **1.1** RED: write a controller/system test for `Accounts::IntegrationsController#show` asserting:
  - Account with flag ON sees the `_google_ads_card` partial, regardless of `Rails.env`
  - Account with flag OFF sees `_coming_soon_card` for Google Ads
  - Existing Meta behavior unaffected
- [x] **1.2** GREEN: edit `app/views/accounts/integrations/show.html.erb:26` to replace
  ```erb
  <% if Rails.env.production? %>
    <%= render "coming_soon_card", platform: "Google Ads", notified: @notified_platforms.include?("Google Ads") %>
  <% else %>
    <%= render "google_ads_card" %>
  <% end %>
  ```
  with
  ```erb
  <% if current_account.feature_enabled?(FeatureFlags::GOOGLE_ADS_INTEGRATION) %>
    <%= render "google_ads_card" %>
  <% else %>
    <%= render "coming_soon_card", platform: "Google Ads", notified: @notified_platforms.include?("Google Ads") %>
  <% end %>
  ```
  Mirrors the Meta pattern at line 34.
- [x] **1.3** Run `bin/rails test test/controllers/accounts/integrations_controller_test.rb test/system/integrations_test.rb`. All green.
- [ ] **1.4** Manual smoke on dev: toggle flag for a test account; reload `/account/integrations`; confirm card swaps; click Connect; OAuth flow runs; smoke a dry-run callback. **User action.**
- [x] **1.5** Commit: `fix(integrations): gate Google Ads card on feature flag, not Rails.env`

### Phase 2 — Bulk-enable for paid accounts (code ✅ · prod run pending)

Status: rake task shipped 2026-05-15 in commit `8c33104`. Dry-run smoke against dev DB passed (1 paid account, flag already on). Prod run gated on Phase 0 confirmation.

- [x] **2.1** Write `lib/tasks/google_ads_rollout.rake` with `google_ads_rollout:enable_for_paid_accounts` task:
  - Iterate `Account.where(plan: <paid plans>)` (use the existing scope on `Account::Billing` if there is one, else inline the predicate)
  - For each account: skip if `feature_enabled?(FeatureFlags::GOOGLE_ADS_INTEGRATION)` already true
  - Else `enable_feature!(FeatureFlags::GOOGLE_ADS_INTEGRATION)` and log `Enabled google_ads_integration for #{account.prefix_id} (#{account.name})`
  - Print summary at end: enabled X, skipped Y already-on, skipped Z non-paid
  - Idempotent (rerun should no-op for accounts already enabled)
- [x] **2.2** RED: test the rake task against a fixture set: paid + flag OFF (gets enabled), paid + flag ON (skipped), free (skipped). Verify counts. (6 tests in `test/tasks/google_ads_rollout_test.rb`)
- [x] **2.3** GREEN: implement, all tests pass.
- [ ] **2.4** Dry-run on prod: `DRY_RUN=true bin/rails google_ads_rollout:enable_for_paid_accounts`. Sanity-check the count vs admin dashboard's "paid accounts" figure. **User action.**
- [ ] **2.5** Run in prod: `bin/rails google_ads_rollout:enable_for_paid_accounts`. Capture stdout to a file for audit. **User action — gated on Phase 0.**
- [ ] **2.6** Spot-check 3 paid accounts: log in as the account owner (impersonation), confirm Google Ads card is live. **User action.**
- [x] **2.7** Commit: `feat(integrations): rake task to bulk-enable Google Ads for paid accounts`

### Phase 3 — Marketing copy + cross-spec links

- [ ] **3.1** `app/views/pages/pricing.html.erb:41-42` already says "Paid plans connect Google Ads (with Meta and LinkedIn coming)". Verify still accurate post-rollout. No edit expected.
- [ ] **3.2** `app/views/pages/pricing.html.erb:82` says "Google Ads is live today. Meta and LinkedIn are next." Already accurate.
- [ ] **3.3** Scan landing pages, blog posts, onboarding email templates for "Google Ads coming soon" / "private beta" copy. Replace with present-tense "live" copy where found.
- [ ] **3.4** Update `lib/specs/ad_platforms_meta_rollout_spec.md` Phase 5 status from "blocked on Google OAuth verification" to "unblocked: see `google_ads_rollout_spec.md`".
- [ ] **3.5** Update `lib/specs/platform_api_approvals_spec.md` Google row in the status table once Phase 0 confirms verified.
- [ ] **3.6** Update `project_google_ads_api_status` memory: developer token Basic ✅, OAuth verified ✅ (date), Standard denied (date, reapply policy noted).
- [ ] **3.7** Commit: `docs(specs): mark Google Ads GA rollout complete, unblock Meta Phase 5`

### Phase 4 — Move this spec to old/

- [ ] **4.1** After Phases 0-3 are green and merged: `git mv lib/specs/google_ads_rollout_spec.md lib/specs/old/`
- [ ] **4.2** Final commit: `docs(specs): archive google_ads_rollout_spec post-GA`

---

## Testing Strategy

### Unit / Controller Tests

| Test | File | Verifies |
|---|---|---|
| Integrations page renders live card when flag ON | `test/controllers/accounts/integrations_controller_test.rb` | Phase 1.2 view change |
| Integrations page renders Coming Soon when flag OFF | `test/controllers/accounts/integrations_controller_test.rb` | Phase 1.2 view change |
| OAuth controller still gates on flag (regression) | `test/controllers/oauth/google_ads_controller_test.rb` | Pre-existing guard, no regression |
| Rake task enables only paid accounts | `test/tasks/google_ads_rollout_test.rb` | Phase 2 idempotency + scoping |
| Rake task is idempotent | same | Rerun produces zero additional enables |

No mocks (per `feedback_no_mocks.md`). Tests use fixtures and real records.

### Manual QA (after Phase 1, before Phase 2 prod run)

1. Log in as a paid account with flag OFF → see Coming Soon card
2. `bin/rails feature_flags:enable ACCT=acct_xxx FLAG=google_ads_integration`
3. Reload `/account/integrations` → live Google Ads card visible
4. Click Connect → OAuth flow runs → consent screen has no unverified warning (already confirmed Phase 0)
5. Complete OAuth with a Google Ads account that has at least one MCC customer
6. Land on `select_account` view, pick a customer, optionally add metadata
7. Confirm new `AdPlatformConnection` exists with `platform: google_ads`, `account_id` matches
8. Wait for or trigger `AdPlatforms::Google::SpendSyncService` → confirm `ad_spend_records` populated
9. Cross-account isolation spot check: log in as a different paid account, verify no Google Ads data leak in any dashboard

### Manual QA (after Phase 2 prod run)

1. Pick 3 random paid accounts from the rollout log
2. Confirm `account.feature_enabled?(FeatureFlags::GOOGLE_ADS_INTEGRATION)` returns true in prod console
3. Confirm at least one account-owner login shows the live card on the integrations page
4. Confirm a non-paid account still sees Coming Soon (rake task scoping worked)

---

## Definition of Done

- [ ] Phase 0 incognito test confirms no unverified-app warning (or rollout aborts)
- [ ] Phase 1: view gate flipped, all tests green, deployed to prod
- [ ] Phase 2: rake task ran in prod, stdout captured, paid-account count matches expectation
- [ ] Phase 3: marketing copy verified, cross-spec links updated, memory updated
- [ ] Meta rollout Phase 5 (`ad_platforms_meta_rollout_spec.md`) is unblocked and can run on pet-resort prod
- [ ] No regressions in Meta integration (Meta flag-gating identical pattern, no shared code changed)
- [ ] Spec moved to `lib/specs/old/`

---

## Out of Scope

- **Conversion push (offline conversion imports, Enhanced Conversions).** Separate spec at `lib/specs/future/google_ads_conversion_push_spec.md`. Requires amending the API Center application (declared read-only today) and a privacy-policy update before any code lands. Customer opt-in per connection, dedicated conversion action to prevent double-counting with their existing pixel.
- **Reapplying for Standard Access.** Auto-denied 30 Apr 2026 because daily ops are below 15k. Reapply when traffic justifies; tracked in `platform_api_approvals_spec.md`.
- **New-signup defaults.** Phase 2 enables for existing paid accounts. Whether new signups get the flag by default at account creation is an open question (see below). Out of scope for this rollout; can be a one-line change later if we decide yes.
- **Removing the feature flag entirely.** Until we're confident in production volume + error rates, the flag stays as a kill switch. Remove after a clean quarter.
- **Pricing page redesign.** Copy is already accurate. No design changes.

---

## Open Questions

1. **New-signup default.** Should `Account#after_create` enable `GOOGLE_ADS_INTEGRATION` by default for paid plans? Cleaner than rerunning the rake task quarterly, but couples flag policy to billing. **Lean: yes, add to `Plan` model as `default_feature_flags` array.** Defer to a follow-up spec; don't bloat this rollout.
2. **Free-trial accounts.** Right now `require_paid_plan` blocks at OAuth entry but the live card would still appear if we enabled the flag for free accounts. Today the rake task scopes to paid only, so free accounts stay on Coming Soon. Worth a UX review: do we want trial accounts to see the live card with a "Upgrade to connect" CTA, or stay on Coming Soon? **Lean: Coming Soon, current behavior, no change.**
3. **Conversion-push readiness signal.** When we ship the future conversion-push spec, should existing Google Ads connections auto-prompt customers to opt in? Or strictly require a fresh connection? **Defer to that spec.**
