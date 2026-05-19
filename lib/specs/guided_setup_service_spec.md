# Guided Setup Service Specification

**Date:** 2026-05-19
**Priority:** P1
**Status:** Ready
**Branch:** `feat/guided-setup-service`

---

## Summary

mbuzz will offer **Guided Setup** — a done-for-you onboarding service in which an mbuzz specialist installs the four API calls, connects one integration the customer already has (Meta Ads, Google Ads, or sGTM), and runs a training call.

Onboarding starts with one question — **"How do you want to set up mbuzz?"** — with three paths:

- **I'll set it up myself** → the existing self-serve flow (API key, SDK, install, verify).
- **A teammate will** → mbuzz's existing team-invitation flow.
- **I'd like help** → discovery → Guided Setup.

On the help path the customer **pays $1,500**, chooses a plan, and the full $1,500 is granted back as **account credit** applied to that plan immediately. The setup costs the customer nothing net; they have prepaid their subscription. The priority is **customer acquisition** — mbuzz absorbs the ~$500 of specialist time as acquisition cost and does not charge a margin on the service.

This spec is the signed-off plan; the wireframes in `lib/mockups/` are its companion. Annual billing was considered and dropped — see `lib/specs/future/annual_plans_spec.md`.

---

## Current State

### Onboarding

A 9-step self-serve bitmask funnel.

- `app/controllers/onboarding_controller.rb` — controller; routes at `config/routes.rb:137-149`
- `app/models/concerns/account/onboarding.rb` — `ONBOARDING_STEPS`, `onboarding_progress` bitmask
- `app/views/onboarding/` — `show` (persona), `setup`, `install`, `verify`, `conversion`, `attribution`
- `accounts.onboarding_persona` (enum) — set by the first screen; marketers route straight to a demo-data dashboard

The first screen asks **persona** (developer / marketer / both). There is no qualification and no human-assisted path.

### Team invitations (already exists — reused, not built)

- `app/services/team/invitation_service.rb`, `acceptance_service.rb`, `removal_service.rb`
- `app/models/account_membership.rb`, `app/controllers/accounts/team/invitations_controller.rb`, `app/controllers/invitations_controller.rb`, `app/mailers/team_mailer.rb`

### Billing

- `app/models/plan.rb` — `Plan`: `slug`, `monthly_price_cents`, `stripe_price_id`
- `app/models/concerns/account/billing.rb` — billing logic on `Account`; `billing_status` enum
- `app/constants/billing.rb` — prices, limits, periods
- `app/services/billing/checkout_service.rb` — Stripe Checkout (subscription mode)
- `app/services/billing/handlers/*` — `invoice_paid`, `invoice_payment_failed`, `subscription_updated`, `subscription_deleted`, `checkout_completed`

Plan tiers (monthly): Free $0, Starter $29, Growth $99, Pro $299. **There is no account-credit concept** today.

---

## Proposed Solution

### Flow

```
signup
  │
  ▼
[ How do you want to set up mbuzz? ]   ← new first screen, replaces persona
  │
  ├── self_serve  → existing flow: Setup → Install → Verify → Conversion → Attribution
  ├── teammate    → existing Team::InvitationService invite flow
  └── assisted    → Discovery (4 questions) → Guided Setup (details + plan)
                    → $1,500 Stripe Checkout → Confirmation
```

### Four pieces

1. **Setup-choice screen** — replaces persona; records `accounts.setup_path` and routes.
2. **Account credit** — an `account_credits` ledger plus a Stripe customer-credit-balance grant.
3. **Guided Setup engagement** — a `GuidedSetup` record tracking the 4-touchpoint concierge engagement.
4. **Discovery** — a 4-question profile, assisted path only, as context for the specialist.

### Offer Mechanics

- One **$1,500 payment** at checkout; the customer chooses a plan in the same flow.
- The full **$1,500 is granted as credit** to the Stripe customer balance and the chosen plan's subscription starts immediately, drawing the credit down. Normal billing resumes when the credit is exhausted.
- **Spend-right-away:** the credit is committed to the chosen plan at purchase — no banked balance, no expiry machinery.
- **Non-refundable:** neither the $1,500 nor any unconsumed credit is refundable; remaining credit is forfeited on cancellation.
- **No fit score / no gating** — the customer self-selects "I'd like help"; anyone on that path can buy. The specialist team's capacity is the only throttle, managed operationally.

### Data Flow (Proposed)

```
choose "I'd like help"
  → accounts.setup_path = assisted
  → /onboarding/discovery  (answers → accounts.setup_profile jsonb)
  → /onboarding/guided_setup  (plan picker, recommended tier from ad-spend answer)
  → accept → create GuidedSetup (pending)
  → Billing::CreditCheckoutService → Stripe Checkout (mode: payment, $1,500,
                                     metadata: guided_setup=true, plan_id)
  → checkout.session.completed (mode: payment)
  → Billing::Handlers::CreditPurchaseCompleted
       → Billing::GrantCreditService (Stripe customer credit balance + AccountCredit row)
       → start the chosen plan's subscription
       → GuidedSetup → in_progress
       → GuidedSetupMailer (customer welcome; internal notification)
  → /onboarding/confirmation  (optional preferred-call-times → GuidedSetup.scheduling_note)
  → specialist delivers: kickoff → install → integration → training → value check
  → GuidedSetup → delivered
```

### Key Files

| File | Purpose |
|------|---------|
| `db/migrate/*_create_account_credits.rb` | `account_credits` table |
| `db/migrate/*_create_guided_setups.rb` | `guided_setups` table |
| `db/migrate/*_add_setup_path_to_accounts.rb` | `accounts.setup_path` |
| `db/migrate/*_add_setup_profile_to_accounts.rb` | `accounts.setup_profile` jsonb + `setup_profile_completed_at` |
| `app/constants/billing.rb` | `GUIDED_SETUP_CREDIT_CENTS` |
| `app/models/account_credit.rb` | Credit grant ledger row |
| `app/models/guided_setup.rb` | Engagement state machine + milestones |
| `app/models/concerns/account/billing.rb` | `credit_balance_cents`, `has_many :account_credits` |
| `app/services/billing/credit_checkout_service.rb` | One-time $1,500 Stripe Checkout |
| `app/services/billing/grant_credit_service.rb` | Stripe customer balance credit + ledger row |
| `app/services/billing/handlers/credit_purchase_completed.rb` | Webhook handler |
| `app/services/billing/handlers/subscription_deleted.rb` | Existing — void the credit on cancellation |
| `app/controllers/onboarding_controller.rb` | Setup-choice, discovery, guided_setup, accept, confirmation |
| `app/controllers/admin/guided_setups_controller.rb` | Manage engagements; `skip_marketing_analytics` |
| `app/mailers/guided_setup_mailer.rb` | Customer welcome + internal notification |
| `app/views/onboarding/show.html.erb` | Setup-choice screen (replaces persona) |
| `app/views/onboarding/discovery.html.erb` | 4-question discovery form |
| `app/views/onboarding/guided_setup.html.erb` | Details + plan picker |
| `app/views/onboarding/confirmation.html.erb` | Post-purchase confirmation |

---

## Account Credit Detail

The **Stripe customer credit balance** applies the credit automatically to every invoice. mbuzz keeps an **`account_credits` ledger** as the record of the grant — for display and audit. The live remaining balance is the Stripe balance, shown on the billing page (cached ~5 min). There is **no expiry**: the credit is committed to an active subscription at purchase.

### Schema (`account_credits`)

- `account_id` (fk) — multi-tenancy
- `amount_cents` (integer) — the grant ($1,500 → `150_000`)
- `source` (string) — `guided_setup`
- `applied_plan_id` (fk → `plans`) — the plan the customer chose to fund
- `status` (integer enum) — `{ active: 0, voided: 1 }`
- `granted_at` (datetime)
- `stripe_balance_transaction_id` (string)
- `notes` (text, nullable)
- `prefixed_ids` prefix `cred_`

### Constant (`app/constants/billing.rb`)

```
GUIDED_SETUP_CREDIT_CENTS = 150_000   # $1,500
```

### Services & Rules

- **`Billing::GrantCreditService`** — creates a Stripe Customer Balance Transaction crediting `GUIDED_SETUP_CREDIT_CENTS`, writes an `AccountCredit` row (`active`). Inherits `ApplicationService`.
- **`Billing::Handlers::SubscriptionDeleted`** (extended) — on cancellation, marks the account's `active` `AccountCredit` `voided`. No refund.
- Credit is non-refundable and account-bound. One Guided Setup, one credit grant per account.

---

## Guided Setup Detail

### The Service

A productized, fixed-scope engagement — four touchpoints, ~30 days, kickoff non-negotiable:

1. **Kickoff call** — confirm goals, agree a written success plan, define the value moment.
2. **Install** — the specialist implements the four API calls (`session`, `event`, `conversion`, `identify`).
3. **Integration** — connect one integration mbuzz already supports: Meta Ads, Google Ads, or sGTM. No new integration is built.
4. **Training call** — dashboard + attribution-model walkthrough, plus a 30-day value check.

The **value moment** — the customer seeing one real conversion correctly attributed — is explicit and instrumented.

### `GuidedSetup` Model

`belongs_to :account`, `has_one :guided_setup` on `Account`. Scoped to account.

Columns (`guided_setups`):
- `account_id` (fk)
- `status` (integer enum) — `{ pending: 0, in_progress: 1, delivered: 2, cancelled: 3 }`
- `integration_target` (string) — enum-validated: `meta`, `google_ads`, `sgtm`, `none`
- `specialist_name` (string, nullable)
- `scheduling_note` (text, nullable) — the customer's optional preferred call times, from the confirmation screen
- `accepted_at`, `kickoff_call_at`, `install_completed_at`, `integration_connected_at`, `training_call_at`, `value_check_at`, `completed_at` (datetimes)
- `notes` (text, nullable)
- `prefixed_ids` prefix `gst_`

Behaviour: created `pending` on offer acceptance; the credit-purchase webhook moves it to `in_progress` and stamps `accepted_at`; a specialist stamps milestones via admin; stamping `value_check_at` moves it to `delivered` and sets `completed_at`. Extract `GuidedSetup::Relationships` and `GuidedSetup::Scopes` (`in_progress`, `stalled` — in progress, no milestone in 14 days).

### Admin

`Admin::GuidedSetupsController` — index (`stalled` highlighted), show, update (stamp milestones, assign specialist, edit notes). Shows the customer's `scheduling_note`. Declares `skip_marketing_analytics`. Uses `find` with prefixed IDs.

### Booking & Emails

No scheduling tool. The confirmation screen captures an optional `scheduling_note`; the specialist emails the customer to arrange the calls. `GuidedSetupMailer` — `welcome` (to the customer: what to expect, the four touchpoints) and `internal_notification` (to the mbuzz team address, read from credentials — **no email address in git**).

---

## Setup-Choice Screen

The first onboarding screen (`OnboardingController#show`) becomes **"How do you want to set up mbuzz?"** — three cards. `#choose_path` (POST) stores `accounts.setup_path` and routes:

- `self_serve` → existing `/onboarding/setup`
- `teammate` → the existing team-invitation new page
- `assisted` → `/onboarding/discovery`

`accounts.setup_path` — integer enum `{ self_serve: 0, teammate: 1, assisted: 2 }`, nullable until chosen.

The old `onboarding_persona` column and persona view are superseded. `onboarding_persona` is **left in place** (no destructive column drop) but no longer populated. The persona screen's one behavioural side effect — marketers routed to a demo-data dashboard — is **re-homed**: the dashboard shows sample/demo data for any account with no real events yet, independent of persona.

---

## Discovery Detail

Shown **only on the assisted path**, after the setup-choice screen.

### Schema (`accounts`)

- `setup_profile` (jsonb, default `{}`) — validate `is_a?(Hash)` and the 50KB JSONB limit
- `setup_profile_completed_at` (datetime, nullable)

### The Four Questions

Every question has an **"Other"** option with a free-text input.

| # | Question | Answers | Stored key |
|---|----------|---------|-----------|
| 1 | What are you trying to attribute? | ecommerce purchases / B2B leads & deals / signups & subscriptions / Other… | `attribution_goal` |
| 2 | Which ad platforms do you run? (multi) | Meta / Google Ads / TikTok / LinkedIn / None / Other… | `ad_platforms` |
| 3 | Which platform(s) is mbuzz going on? (multi) | Ruby / Python / Node.js / PHP / sGTM / Shopify / Magento / REST API / Other… | `install_platforms` |
| 4 | Monthly ad spend? | <$5k / $5–25k / $25–100k / $100k+ / Other… | `monthly_ad_spend` |

Answers are context for the specialist; `monthly_ad_spend` recommends a tier on the Guided Setup page. **No fit score** — there is nothing to gate once the customer has chosen the help path.

---

## Guided Setup Page, Purchase & Confirmation

### Guided Setup page (`/onboarding/guided_setup`)

The details + plan picker for the assisted path (not a pushed offer). Shows the four touchpoints, the **$1,500 → credit** mechanics, and a plan picker (Starter / Growth / Pro) with the tier matching `monthly_ad_spend` pre-selected. Terms stated plainly: applied to the chosen plan now, non-refundable, cannot be saved.

### Purchase

- **Accept** (a plan is selected) → create `GuidedSetup` (`pending`, `integration_target` inferred from `setup_profile`), call `Billing::CreditCheckoutService`, redirect to Stripe Checkout — **mode `payment`**, one $1,500 line item, metadata `guided_setup=true` + `plan_id`.
- `checkout.session.completed` with **`mode == "payment"`** + `guided_setup` metadata → `Billing::Handlers::CreditPurchaseCompleted`: grant credit, start the chosen plan's subscription, transition `GuidedSetup` to `in_progress`, fire `GuidedSetupMailer`. The webhook router branches on `session.mode`; the existing `checkout_completed` handler keeps `mode == "subscription"`.
- **Abandoned** → `GuidedSetup` stays `pending`; no charge, credit, or subscription.

### Confirmation (`/onboarding/confirmation`)

Post-purchase: confirms the credit and subscription, captures an optional free-text **preferred call times** → `GuidedSetup.scheduling_note`.

---

## All States

| State | Condition | Behaviour |
|-------|-----------|-----------|
| Path not chosen | `setup_path` nil | Show the setup-choice screen |
| Path = self_serve | choice saved | Existing self-serve onboarding |
| Path = teammate | choice saved | Redirect to the team-invitation flow |
| Path = assisted | choice saved | Route to `/onboarding/discovery` |
| Discovery incomplete | `setup_profile_completed_at` nil | Show discovery |
| Offer shown, no plan | on the Guided Setup page | Primary CTA disabled until a plan is chosen |
| Offer accepted | plan chosen, "Get Guided Setup" | Create `GuidedSetup` pending; redirect to $1,500 Checkout |
| Checkout abandoned | returns without paying | `GuidedSetup` stays `pending`; no charge/credit/subscription |
| Payment completed | `checkout.session.completed`, `mode=payment` | Credit granted; chosen plan started; `GuidedSetup` → `in_progress`; emails sent |
| Credit drawing down | active subscription invoices | Stripe applies the credit automatically |
| Credit exhausted | Stripe credit balance hits zero | Normal monthly billing resumes on the card on file |
| Account cancelled with credit left | subscription cancelled | Remaining credit forfeited; `AccountCredit` → `voided`; `GuidedSetup` → `cancelled` if not delivered |
| Engagement stalled | `in_progress`, no milestone in 14 days | Surfaced in the admin `stalled` scope |
| Engagement delivered | `value_check_at` stamped | `GuidedSetup` → `delivered`, `completed_at` set |
| Empty discovery submit | required answers missing | Re-render with errors; `setup_profile` unchanged |

---

## Implementation Tasks

### Phase 1: Account Credit

- [ ] **1.1** Migration: create `account_credits`
- [ ] **1.2** `AccountCredit` model — `status` enum (`active`/`voided`), `cred_` prefix, scopes
- [ ] **1.3** `Account::Billing`: `has_many :account_credits`, `credit_balance_cents` (Stripe customer balance, cached)
- [ ] **1.4** `app/constants/billing.rb`: `GUIDED_SETUP_CREDIT_CENTS`
- [ ] **1.5** `Billing::GrantCreditService` — Stripe customer balance credit + `AccountCredit` row
- [ ] **1.6** Extend `Billing::Handlers::SubscriptionDeleted` — void the credit on cancellation
- [ ] **1.7** Tests

### Phase 2: Guided Setup Engagement

- [ ] **2.1** Migration: create `guided_setups` (incl. `scheduling_note`)
- [ ] **2.2** `GuidedSetup` model + `Relationships`/`Scopes` concerns; `status` enum; milestone methods; `gst_` prefix
- [ ] **2.3** `Account` `has_one :guided_setup`
- [ ] **2.4** `Admin::GuidedSetupsController` + index/show/update views — declare `skip_marketing_analytics`
- [ ] **2.5** Tests

### Phase 3: Setup-Choice Screen + Routing

- [ ] **3.1** Migration: add `setup_path` to `accounts`
- [ ] **3.2** `Account`: `setup_path` enum
- [ ] **3.3** `OnboardingController#show` renders the setup-choice screen; `#choose_path` (POST) stores `setup_path` and routes the three paths
- [ ] **3.4** `onboarding/show.html.erb` → setup-choice screen; routes
- [ ] **3.5** Re-home demo data — dashboard shows sample data for any account with no real events, decoupled from `onboarding_persona`
- [ ] **3.6** Tests

### Phase 4: Discovery

- [ ] **4.1** Migration: add `setup_profile` jsonb + `setup_profile_completed_at` to `accounts`
- [ ] **4.2** `Account`: JSONB validation (`is_a?(Hash)`, 50KB limit)
- [ ] **4.3** `OnboardingController#discovery` GET/POST — assisted path only; stores `setup_profile`
- [ ] **4.4** `onboarding/discovery.html.erb` — 4 questions, each with an "Other" free-text
- [ ] **4.5** Tests

### Phase 5: Guided Setup Page + Credit Purchase

- [ ] **5.1** `OnboardingController#guided_setup`, `accept` (requires `plan_id`), `confirmation` + routes
- [ ] **5.2** `onboarding/guided_setup.html.erb` + `confirmation.html.erb` (captures `scheduling_note`)
- [ ] **5.3** `Billing::CreditCheckoutService` — $1,500 Stripe Checkout (mode `payment`), `guided_setup` + `plan_id` metadata
- [ ] **5.4** `Billing::Handlers::CreditPurchaseCompleted` — router branches on `session.mode`; grant credit, start the chosen plan's subscription, transition `GuidedSetup`
- [ ] **5.5** `GuidedSetupMailer` — `welcome`, `internal_notification`
- [ ] **5.6** Audit `skip_marketing_analytics` on `OnboardingController` and `Accounts::BillingController`
- [ ] **5.7** Tests

### Phase 6: Billing Surface, Analytics, Docs

- [ ] **6.1** Credit balance + Guided Setup offer card on `accounts/billing/show.html.erb`
- [ ] **6.2** `Lifecycle::Tracker` events: `setup_path_chosen`, `discovery_completed`, `guided_setup_accepted`, `credit_granted`
- [ ] **6.3** Admin metric: assisted-path → purchase conversion; activation within 30/60 days
- [ ] **6.4** Update `lib/docs/BUSINESS_RULES.md` (billing — credits) and `lib/docs/PRODUCT.md`
- [ ] **6.5** Move this spec to `lib/specs/old/` on completion

---

## Testing Strategy

No mocks or stubs — test outcomes and business logic directly. Stripe is covered by the existing webhook-handler test approach.

| Test | File | Verifies |
|------|------|----------|
| Credit grant | `test/services/billing/grant_credit_service_test.rb` | Stripe balance credited $1,500; `AccountCredit` row `active`, `applied_plan_id` set |
| Credit voided on cancel | `test/services/billing/handlers/subscription_deleted_test.rb` | Cancellation marks the `AccountCredit` `voided`; no refund |
| Credit checkout | `test/services/billing/credit_checkout_service_test.rb` | Session `mode: payment`, $1,500, `guided_setup` + `plan_id` metadata |
| Webhook routing | `test/services/billing/handlers/credit_purchase_completed_test.rb` | `mode=payment` grants credit, starts the chosen subscription, transitions `GuidedSetup`; `mode=subscription` untouched |
| Engagement lifecycle | `test/models/guided_setup_test.rb` | Milestone stamps transition status; `value_check_at` → `delivered`; `stalled` scope |
| Setup-path routing | `test/controllers/onboarding_controller_test.rb` | Each `setup_path` choice routes correctly |
| Discovery persistence | `test/controllers/onboarding_controller_test.rb` | `setup_profile` stored; "Other" free-text captured; required answers validated |
| Cross-account isolation | model + controller tests | No account can read another's `GuidedSetup` or `AccountCredit` |

### Manual QA (dev)

1. New signup → setup-choice → "I'd like help" → discovery → Guided Setup page (recommended tier pre-selected).
2. Choose a plan, accept, complete Stripe test checkout (payment mode) → `AccountCredit` granted, Stripe balance credited, chosen plan active, `GuidedSetup` `in_progress`, emails sent.
3. Confirmation screen → enter preferred times → confirm `GuidedSetup.scheduling_note` saved and shown in admin.
4. New signup → "A teammate will" → lands in the existing invitation flow.
5. New signup → "I'll set it up myself" → existing self-serve onboarding, unchanged.
6. Admin → stamp milestones through `value_check_at` → `delivered` + `completed_at`.
7. Cancel a subscription with credit remaining → `AccountCredit` `voided`, nothing refunded.

---

## Definition of Done

- [ ] All tasks completed; tests pass (unit + controller + integration)
- [ ] Manual QA on dev
- [ ] No regressions in the existing onboarding funnel, team invitations, or billing webhooks
- [ ] `skip_marketing_analytics` verified on every controller touching billing, credits, or API keys
- [ ] No secrets or email addresses committed — credentials/placeholders only
- [ ] `BUSINESS_RULES.md` + `PRODUCT.md` updated
- [ ] Spec updated with final decisions and archived to `old/`

---

## Out of Scope

- **Annual billing** — `lib/specs/future/annual_plans_spec.md`.
- **Building any new integration** — Guided Setup connects only what mbuzz already supports.
- **Fit score / offer gating** — removed; the customer self-selects the help path.
- **Banked, transferable, or expiring credit** — the credit is committed to a chosen plan at purchase.
- **Credit refunds** — the $1,500 and any unconsumed credit are non-refundable.
- **Scheduling tool integration** — the specialist arranges calls by email; only a free-text preference is captured.
- **Promo / coupon codes; multi-currency** — credit and pricing are USD.
