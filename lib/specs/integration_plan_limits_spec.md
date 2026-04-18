# Ad Platform Integration Plan Limits Specification

**Date:** 2026-04-18
**Priority:** P1
**Status:** Ready
**Branch:** `feature/integration-plan-limits`

---

## Summary

Ad platform integrations (Google Ads today; Meta and LinkedIn coming) are a paid-plan feature. Paid plans already unlock the connect flow, but there is no per-plan cap on how many platforms an account can connect, and the pricing page doesn't mention integrations at all. This spec caps integrations per plan (Starter: 2, Growth: 5, Pro: unlimited, Enterprise: unlimited), enforces the cap at the OAuth connect boundary, surfaces the usage in the integrations UI, and updates the public pricing pages so the value is visible before signup.

---

## Current State

- **Paid-plan gate exists.** `Account#can_connect_ad_platform?` returns `true` only if `plan.slug` is in `Billing::PAID_PLANS` (`app/models/concerns/account/billing.rb:203-205`). Enforced in `Oauth::GoogleAdsController#connect` (line 11) with a redirect to the integrations page and an upgrade alert. View partial `app/views/accounts/integrations/_connect_button.html.erb` renders the subscription-required modal for non-paid accounts.
- **Limit column exists but is unused.** Migration `db/migrate/20260303060001_add_connection_limit_to_plans.rb` adds `plans.ad_platform_connection_limit:integer`. The column is not populated in `db/seeds.rb` and no code reads it.
- **No UI usage indicator.** `app/views/accounts/integrations/show.html.erb` doesn't show "X of Y integrations used".
- **Pricing page silent on integrations.** `app/views/pages/pricing.html.erb` and `app/views/pages/home/_pricing.html.erb` list event limits, custom model counts, and overage pricing, but not integrations. Schema.org `offers` in `pricing.html.erb:20-25` also omit them.
- **Connection lifecycle.** `AdPlatformConnection` (`app/models/ad_platform_connection.rb`) supports statuses `connected`, `syncing`, `error`, `disconnected`, `needs_reauth`. A disconnected row stays in the DB — the count toward the limit must exclude `disconnected`.

### Data Flow (Current)

```
User clicks "Connect" → Oauth::GoogleAdsController#connect
  → can_connect_ad_platform?  [paid-plan only check]
    → redirect to Google OAuth → callback → select_account → create_connection
      → AdPlatformConnection.save!  [no limit check]
```

---

## Proposed Solution

Populate `plan.ad_platform_connection_limit` from a single source of truth in `Billing`. Add three predicate/accessor methods on `Account::Billing` that mirror the existing `custom_model_limit` / `can_create_custom_model?` pattern. Tighten the OAuth connect gate to check both paid-plan status *and* remaining headroom. Add a second race-safe check at save time. Surface the count in the integrations UI with three button states. Update both pricing surfaces (homepage partial, public pricing page, Schema.org metadata, FAQ copy) to reflect the new value proposition.

Unlimited is modeled as a `nil` column value, mirroring "no cap" conventions used elsewhere. Pro and Enterprise set `ad_platform_connection_limit = nil`.

### Data Flow (Proposed)

```
User clicks "Connect" → Oauth::GoogleAdsController#connect
  → can_add_ad_platform_connection?  [paid-plan AND remaining > 0]
    → redirect_with_limit_error  (not paid)  OR
    → redirect_with_at_limit_error  (paid but at cap)  OR
    → redirect to Google OAuth → callback → select_account → create_connection
      → can_add_ad_platform_connection?  [race-safe re-check]
        → AdPlatformConnection.save!
```

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/constants/billing.rb` | Single source of truth for plan constants | Add `AD_PLATFORM_CONNECTION_LIMITS` hash |
| `db/seeds.rb` | Seed plan rows | Assign `ad_platform_connection_limit` from constant |
| `app/models/concerns/account/billing.rb` | Account plan predicates | Add `ad_platform_connection_limit`, `ad_platform_connections_remaining`, `can_add_ad_platform_connection?` |
| `app/controllers/oauth/google_ads_controller.rb` | OAuth connect flow | Use new predicate in `#connect`; re-check in `#create_connection`; add `redirect_with_at_limit_error` |
| `app/views/accounts/integrations/_connect_button.html.erb` | Connect CTA | 3 states: has-room / at-limit (new upgrade modal) / no-paid-plan (existing modal) |
| `app/views/accounts/integrations/show.html.erb` | Integrations page | Add "X of Y" usage badge (or "Unlimited") |
| `app/views/accounts/integrations/_at_limit_modal.html.erb` | NEW | Upgrade modal for paid accounts that hit the cap |
| `app/views/pages/home/_pricing.html.erb` | Homepage pricing table | Add "Ad Integrations" column |
| `app/views/pages/pricing.html.erb` | Public pricing page | Update Schema.org `offers`, add FAQ entry, copy tweak |
| `test/models/account/billing_test.rb` | Unit tests | Limits, remaining math, unlimited, disconnected exclusion |
| `test/controllers/oauth/google_ads_controller_test.rb` | Controller tests | Gate behavior across plan × usage states |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Free plan, any usage | `plan.free?` | Connect button visible, click opens subscription-required modal (existing) |
| Starter, 0–1 connected | `plan == starter && count < 2` | Connect button → OAuth flow |
| Starter, 2 connected | `plan == starter && count >= 2` | Connect button visible, click opens at-limit modal (upgrade CTA) |
| Growth, 0–4 connected | `plan == growth && count < 5` | Connect button → OAuth flow |
| Growth, 5 connected | `plan == growth && count >= 5` | At-limit modal |
| Pro / Enterprise | `plan.ad_platform_connection_limit.nil?` | Connect button → OAuth flow, always |
| Disconnected connections present | `status: disconnected` rows | Excluded from count (user reclaims a slot on disconnect) |
| Race at save | Two tabs open, both complete OAuth | Second `create_connection` re-checks; over-limit → redirect with at-limit alert, nothing saved |
| Plan missing (`plan == nil`) | New account pre-provisioning | Treat as free: limit = 0, `can_add_ad_platform_connection?` → false |
| Existing accounts already over limit | Grandfathering | **Not addressed** (see Out of Scope). Cap only blocks new connections. |

---

## Implementation Tasks

### Phase 1: Data & domain logic

- [ ] **1.1** Add `Billing::AD_PLATFORM_CONNECTION_LIMITS = { PLAN_FREE => 0, PLAN_STARTER => 2, PLAN_GROWTH => 5, PLAN_PRO => nil, PLAN_ENTERPRISE => nil }.freeze` to `app/constants/billing.rb` (nil = unlimited).
- [ ] **1.2** Update `db/seeds.rb`: set `ad_platform_connection_limit: Billing::AD_PLATFORM_CONNECTION_LIMITS.fetch(plan_attrs[:slug])` on each plan hash. Idempotent (existing `find_or_initialize_by` pattern).
- [ ] **1.3** Add to `app/models/concerns/account/billing.rb` under the "Ad Platform Connections" section:
  - `ad_platform_connection_limit` — reads `plan&.ad_platform_connection_limit`, returns `0` if plan nil.
  - `ad_platform_connections_used` — count of non-disconnected `ad_platform_connections`.
  - `ad_platform_connections_remaining` — `Float::INFINITY` if limit nil, else `[limit - used, 0].max`.
  - `ad_platform_connections_unlimited?` — `ad_platform_connection_limit.nil? && plan_is_paid?` guard.
  - `can_add_ad_platform_connection?` — `can_connect_ad_platform? && ad_platform_connections_remaining > 0`.
- [ ] **1.4** Write tests: `test/models/account/billing_test.rb` per Testing Strategy below.

### Phase 2: Controller enforcement

- [ ] **2.1** Change `Oauth::GoogleAdsController#connect` (line 11) to `can_add_ad_platform_connection?`; keep existing `redirect_with_limit_error` for the unpaid case; add `redirect_with_at_limit_error` for the paid-but-full case. Branch on `can_connect_ad_platform?` to pick the right redirect.
- [ ] **2.2** Add race-safe re-check at the top of `#create_connection`: if `!can_add_ad_platform_connection?`, call `clear_oauth_session!` and `redirect_with_at_limit_error`. Place before `duplicate_connection?` check.
- [ ] **2.3** Add `redirect_with_at_limit_error` private method with copy: "You've connected {n} of {n} integrations on your {plan} plan. Upgrade to connect more."
- [ ] **2.4** Verify `skip_marketing_analytics` is still declared (it is, line 5). OAuth params include tokens in flight — no new sensitive surfaces introduced.
- [ ] **2.5** Write tests: `test/controllers/oauth/google_ads_controller_test.rb` per Testing Strategy.

### Phase 3: Integrations UI

- [ ] **3.1** Create `app/views/accounts/integrations/_at_limit_modal.html.erb` — same structure as existing subscription-required modal, different copy pointing to the upgrade path.
- [ ] **3.2** Update `app/views/accounts/integrations/_connect_button.html.erb` to three branches:
  1. `current_account.can_add_ad_platform_connection?` → live link to `oauth_google_ads_connect_path`
  2. `current_account.can_connect_ad_platform?` → button opens `at-limit-modal`
  3. else → button opens existing `subscription-required-modal` (unchanged)
- [ ] **3.3** Render `_at_limit_modal` from `app/views/accounts/integrations/show.html.erb` alongside the existing subscription-required modal.
- [ ] **3.4** Add a usage badge near the page heading in `show.html.erb`: "{used} of {limit} integrations used" or "Unlimited integrations" when `ad_platform_connections_unlimited?`. Use an existing helper/partial if one fits; keep it stylistically consistent with the page.
- [ ] **3.5** No new Stimulus controller — reuse the existing `modal` controller already used for the subscription-required modal.

### Phase 4: Public pricing pages

- [ ] **4.1** `app/views/pages/home/_pricing.html.erb`: add a new column "Ad Integrations" between "Monthly Records" and "Price/Month". Values: Free `—`, Starter `2`, Growth `5`, Pro `Unlimited`.
- [ ] **4.2** `app/views/pages/pricing.html.erb`: update Schema.org `offers` descriptions (lines 22–24) to mention integration counts (e.g., "... 2 ad platform integrations.").
- [ ] **4.3** `app/views/pages/pricing.html.erb`: add a new FAQ section "Which ad platforms are supported?" — Google Ads live; Meta and LinkedIn coming. Clarify that integrations require a paid plan.
- [ ] **4.4** Update hero subtitle copy on `pricing.html.erb` (lines 40–42) to mention "Connect Google Ads, Meta, and LinkedIn to attribute spend" (paid plans).
- [ ] **4.5** Update `lib/docs/BUSINESS_RULES.md` section 9 (Billing) with the new per-plan integration cap. Add a row to any plan-comparison table.
- [ ] **4.6** Run seeds against dev DB so counts match production config when deployed.

---

## Testing Strategy

No mocks. Fixtures + memoized helpers (per `feedback_no_mocks.md`, `feedback_code_style.md`).

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| `ad_platform_connection_limit returns 0 for free` | `test/models/account/billing_test.rb` | Free plan → 0 |
| `ad_platform_connection_limit returns 2 for starter` | same | Starter → 2 |
| `ad_platform_connection_limit returns 5 for growth` | same | Growth → 5 |
| `ad_platform_connection_limit returns nil for pro` | same | Pro → nil (unlimited) |
| `ad_platform_connection_limit returns 0 when plan is nil` | same | Nil plan → 0 |
| `ad_platform_connections_used excludes disconnected` | same | `disconnected` rows don't count |
| `ad_platform_connections_remaining returns Float::INFINITY for pro` | same | Unlimited returns infinity |
| `ad_platform_connections_remaining floors at zero` | same | Never negative |
| `can_add_ad_platform_connection? false for free` | same | Free always blocked |
| `can_add_ad_platform_connection? false for starter at 2` | same | Cap reached |
| `can_add_ad_platform_connection? true for pro at 100` | same | Unlimited |

### Controller Tests

| Test | File | Verifies |
|------|------|----------|
| `GET #connect redirects when account is free` | `test/controllers/oauth/google_ads_controller_test.rb` | Unpaid → redirect + unpaid alert copy |
| `GET #connect redirects when starter at limit` | same | Paid but full → redirect + at-limit alert copy |
| `GET #connect initiates oauth when starter has room` | same | Happy path for starter with 1 connected |
| `GET #connect initiates oauth for pro with 100 connected` | same | Pro always allowed |
| `POST #create_connection redirects if account hit limit mid-flow` | same | Race: simulate limit reached between connect and save |
| `POST #create_connection succeeds when within limit` | same | Connection persisted, account isolation respected |
| Cross-account isolation | same | Another account's connections do not affect this account's count |

### Manual QA

1. Seed dev DB; log in as a free-plan account; visit integrations page; click "Connect Account"; verify subscription-required modal opens.
2. Switch account to Starter plan via console; connect one Google Ads account through OAuth; verify usage badge shows "1 of 2 integrations used".
3. Connect a second; verify badge shows "2 of 2"; verify the Connect button now opens the at-limit modal.
4. Attempt to deep-link `/oauth/google_ads/connect` directly; verify redirect + at-limit alert.
5. Disconnect one connection; verify badge returns to "1 of 2" and Connect button is live again.
6. Switch account to Pro; verify badge says "Unlimited integrations"; connect several.
7. Visit `/pricing` (logged out); verify new "Ad Integrations" column; verify FAQ entry; verify hero copy mentions ad integrations.
8. View page source of `/pricing`; verify Schema.org `offers` descriptions mention integration counts.

---

## Definition of Done

- [ ] All phases completed
- [ ] `bin/rails test` passes (unit + controller)
- [ ] Manual QA steps above verified on dev
- [ ] No regressions in existing integrations flow (Google Ads OAuth + disconnect + reconnect still work)
- [ ] `lib/docs/BUSINESS_RULES.md` updated with per-plan integration cap
- [ ] Spec moved to `lib/specs/old/` after merge
- [ ] Commit history follows `feat(integration): ...` / `feat(dashboard): ...` / `feat(marketing): ...` conventions with no AI attribution

---

## Out of Scope

- **Grandfathering accounts already over limit.** Assumed none exist in production (pre-launch feature). If any do, existing connections remain; only new ones are blocked by the new check.
- **Meta and LinkedIn integrations themselves.** Backend for those platforms is not built in this spec. The pricing page mentions them as coming soon; the limit and gate apply uniformly to `AdPlatformConnection` records regardless of platform, so when those platforms ship they inherit the cap automatically.
- **Coming-soon card gating.** Coming-soon cards in the integrations page (`_coming_soon_card.html.erb`) are purely informational today and stay as-is. When a platform ships, its card swaps to the same `_connect_button` partial and inherits the gate.
- **Stripe product/price changes.** Plan prices and Stripe price IDs are unchanged. This is a cap-and-copy change, not a repricing.
- **Annual billing, proration on plan downgrade when over cap, alerts when approaching limit.** Downgrade-with-excess-connections is a future concern; for now, a Pro → Growth downgrade leaves existing connections intact but blocks new ones until the account disconnects enough to fit.
- **Audit log entries for connect/disconnect tied to plan caps.** Existing connection lifecycle logs are sufficient.
