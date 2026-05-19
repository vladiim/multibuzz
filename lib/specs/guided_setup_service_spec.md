# Guided Setup Service Specification

**Date:** 2026-05-19
**Priority:** P1
**Status:** Draft
**Branch:** `feat/guided-setup-service`

---

## Summary

mbuzz will offer **Guided Setup** — a done-for-you onboarding service in which an mbuzz specialist installs the four API calls, connects one integration the customer already has (Meta Ads, Google Ads, or sGTM), and runs a training call.

The offer: the customer **pays $1,500**, chooses a plan **at checkout**, and the entire $1,500 is applied to that plan immediately as **credit**. The setup itself is free — the customer's money becomes their own plan credit. The credit must be spent at purchase (it cannot be banked for later) and is **non-refundable**. The result: the customer is a paying, subscribed, hands-on-onboarded customer from day one.

The priority of this feature is **customer acquisition**, not margin on the service. mbuzz collects $1,500 — all of which funds the customer's own subscription — and absorbs the ~$500 of specialist time as customer-acquisition cost.

The spec adds account credit, a `GuidedSetup` engagement record (kickoff / install / integration / training / 30-day value check), and an onboarding **discovery** step with a **fit score** that routes good-fit accounts to the offer.

Annual billing was explored as the offer mechanism and dropped; it is tracked separately in `lib/specs/future/annual_plans_spec.md`.

---

## Current State

### Onboarding

A 9-step self-serve bitmask funnel.

- `app/controllers/onboarding_controller.rb` — controller; routes at `config/routes.rb:137-149`
- `app/models/concerns/account/onboarding.rb` — `ONBOARDING_STEPS`, `onboarding_progress` bitmask, `current_onboarding_step`, `activated?`
- `app/views/onboarding/` — `show` (persona), `setup`, `install`, `verify`, `conversion`, `attribution`
- `app/mailers/onboarding_mailer.rb` — single `welcome` email

The only question asked of a new account is **persona** (developer / marketer / both). There is no discovery, no qualification, and no human-assisted path.

### Billing

- `app/models/plan.rb` — `Plan`: `slug`, `monthly_price_cents`, `stripe_price_id`
- `app/models/concerns/account/billing.rb` — billing logic on `Account`; `billing_status` enum; `grant_free_until!`
- `app/constants/billing.rb` — prices, limits, periods
- `app/services/billing/checkout_service.rb` — Stripe Checkout (subscription mode)
- `app/controllers/webhooks/stripe_controller.rb` + `app/services/billing/handlers/*` — webhook handling (`invoice_paid`, `invoice_payment_failed`, `subscription_updated`, `subscription_deleted`, `checkout_completed`)

Plan tiers (monthly): Free $0, Starter $29, Growth $99, Pro $299, Enterprise custom. **There is no account-credit concept** today — discounts are granted only as a `free_until` date.

### Data Flow (Current)

```
signup --> /onboarding (persona) --> [marketer] --> /dashboard
                                 \-> [developer/both] --> setup --> install --> verify --> conversion --> attribution
```

No branch ever offers a human or asks a qualifying question.

---

## Proposed Solution

Three coordinated pieces:

1. **Account credit** — an `account_credits` ledger and a credit-grant path backed by the Stripe customer credit balance.
2. **Guided Setup engagement** — a `GuidedSetup` record per account tracking a productized 4-touchpoint concierge engagement.
3. **Onboarding discovery + offer** — a discovery step that profiles the account, a fit score, and an offer page where good-fit accounts buy Guided Setup and choose the plan their $1,500 funds.

### Offer Mechanics

- The customer makes **one $1,500 payment** at checkout, choosing a plan in the same flow.
- The full **$1,500 is granted as credit** and the chosen plan's subscription starts immediately, drawing the credit down. The customer pays nothing further until the credit is exhausted, then normal monthly billing continues on the card already on file.
- **Spend-right-away:** the credit is committed to the chosen plan at purchase. There is no banked balance the customer can hold or redirect later, and therefore **no expiry machinery is needed**.
- **Non-refundable:** neither the $1,500 nor any unconsumed credit is refundable. On cancellation, remaining credit is forfeited.
- The setup service is free; the $1,500 is entirely the customer's plan money.

### Pricing Rationale

The priority is acquisition. mbuzz collects $1,500, every cent of which funds the customer's own subscription, and gains a customer who is subscribed and fully onboarded from day one. The ~$500 of specialist time per engagement is absorbed as customer-acquisition cost — mbuzz is deliberately **not** charging a margin on the service. Because the customer picks a plan and starts paying at checkout, there is no "parked credit" risk: whichever tier they choose, they are an active, committed customer. The `monthly_ad_spend` discovery answer is used to recommend a tier on the offer page so the customer lands on a plan that fits.

### Data Flow (Proposed)

```
signup --> /onboarding (persona) --> /onboarding/discovery (5 questions)
              |
              v
        Onboarding::FitScore
              |
   +----------+-----------+
   | eligible             | not eligible
   v                      v
/onboarding/guided_setup  existing routing
 (offer + plan picker)
   | accept (plan chosen)
   v
create GuidedSetup (pending)
   --> Billing::CreditCheckoutService --> Stripe Checkout (mode: payment, $1,500,
                                          metadata: guided_setup=true, plan_id)
   --> checkout.session.completed (mode: payment)
   --> Billing::Handlers::CreditPurchaseCompleted
        --> Billing::GrantCreditService (Stripe customer credit balance + AccountCredit row)
        --> start the chosen plan's subscription (credit covers the invoices)
        --> GuidedSetup -> in_progress
        --> GuidedSetupMailer (customer welcome + booking link; internal notification)
   --> specialist delivers: kickoff -> install -> integration -> training -> value check
   --> GuidedSetup -> delivered

ongoing: the chosen plan runs off the $1,500 credit; once exhausted, the card on file is billed monthly
```

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `db/migrate/*_create_account_credits.rb` | Credit ledger | New table `account_credits` |
| `db/migrate/*_create_guided_setups.rb` | Engagement table | New table `guided_setups` |
| `db/migrate/*_add_setup_profile_to_accounts.rb` | Discovery answers | New: `setup_profile` jsonb, `setup_profile_completed_at` |
| `app/constants/billing.rb` | Constants | `GUIDED_SETUP_CREDIT_CENTS` |
| `app/models/account_credit.rb` | New model | Credit grant ledger row + status |
| `app/models/guided_setup.rb` | New model | Engagement state machine + milestones |
| `app/models/concerns/account/billing.rb` | Billing logic | `credit_balance_cents`, `has_many :account_credits` |
| `app/services/billing/credit_checkout_service.rb` | New service | One-time $1,500 Stripe Checkout for a chosen plan |
| `app/services/billing/grant_credit_service.rb` | New service | Stripe customer balance credit + ledger row |
| `app/services/billing/handlers/credit_purchase_completed.rb` | New webhook handler | Grant credit, start subscription, transition `GuidedSetup` |
| `app/services/billing/handlers/subscription_deleted.rb` | Existing handler | Void the `AccountCredit` on cancellation |
| `app/services/onboarding/fit_score.rb` | New value object | Score discovery answers, return eligibility |
| `app/controllers/onboarding_controller.rb` | Onboarding flow | `discovery`, `guided_setup`, `accept`, `decline` actions |
| `app/controllers/admin/guided_setups_controller.rb` | New admin controller | Manage engagements; `skip_marketing_analytics` |
| `app/mailers/guided_setup_mailer.rb` | New mailer | Customer welcome + internal notification |
| `app/views/onboarding/discovery.html.erb` | New view | 5-question discovery form |
| `app/views/onboarding/guided_setup.html.erb` | New view | Offer page with plan picker |
| `app/views/accounts/billing/show.html.erb` | Billing page | Show credit balance; Guided Setup offer card |

---

## Account Credit Detail

### Mechanism

The **Stripe customer credit balance** is the application mechanism: a credited (negative) customer balance is drawn down automatically against every invoice of the chosen plan — base subscription and metered overage alike. mbuzz does not re-implement credit application.

mbuzz keeps an **`account_credits` ledger** as the record of the grant — which account, how much, which plan it funded, current status — for display and audit. The live remaining balance is the Stripe customer credit balance, shown on the billing page (fetched at render, cached ~5 minutes).

There is **no expiry**: the credit is committed to an active subscription at purchase, so the only way it ends is consumption (drawn to zero) or cancellation (forfeited).

### Schema (`account_credits`)

- `account_id` (fk) — multi-tenancy
- `amount_cents` (integer) — the grant amount ($1,500 → `150_000`)
- `source` (string) — `guided_setup` (the only source in v1)
- `applied_plan_id` (fk → `plans`) — the plan the customer chose to fund
- `status` (integer enum) — `{ active: 0, voided: 1 }` (`voided` on cancellation; full consumption is derivable from a zero Stripe balance)
- `granted_at` (datetime)
- `stripe_balance_transaction_id` (string) — the Stripe Customer Balance Transaction
- `notes` (text, nullable)
- `prefixed_ids` prefix `cred_`

### Constant (`app/constants/billing.rb`)

```
GUIDED_SETUP_CREDIT_CENTS = 150_000   # $1,500
```

### Services

- **`Billing::GrantCreditService`** — given an account and the chosen plan: creates a Stripe Customer Balance Transaction crediting `GUIDED_SETUP_CREDIT_CENTS`, writes an `AccountCredit` row (`active`). Inherits `ApplicationService`.
- **`Billing::Handlers::SubscriptionDeleted`** (existing handler, extended) — on cancellation, marks the account's `active` `AccountCredit` as `voided`. No cash or pro-rata refund.

### Rules

- Credit is **non-refundable** and account-bound; forfeited on cancellation.
- One Guided Setup, one credit grant per account.
- The credit funds the **paid plan chosen at checkout** — the Free plan is not selectable in the offer (it has no invoices to draw against).

---

## Guided Setup Detail

### The Service

A productized, fixed-scope concierge engagement — four touchpoints, ~30 days, kickoff non-negotiable, the middle flexed to complexity:

1. **Kickoff call** — confirm goals, agree a written success plan, define the value moment.
2. **Install** — an mbuzz specialist implements the four API calls (`session`, `event`, `conversion`, `identify`) for the customer.
3. **Integration** — connect one integration mbuzz already supports that the customer needs: Meta Ads, Google Ads, or sGTM, through the existing integrations UI. No new integration is built.
4. **Training call** — a focused walkthrough of the dashboard and attribution models, plus a 30-day value check.

The **value moment** is explicit and instrumented: *the customer sees one real conversion correctly attributed to a real channel.* The engagement is engineered backward from that event.

### `GuidedSetup` Model

`app/models/guided_setup.rb` — `belongs_to :account`, `has_one :guided_setup` on `Account`. Scoped to account.

Columns (`guided_setups`):
- `account_id` (fk)
- `status` (integer enum) — `{ pending: 0, in_progress: 1, delivered: 2, cancelled: 3 }`
- `integration_target` (string) — enum-validated: `meta`, `google_ads`, `sgtm`, `none`
- `specialist_name` (string, nullable) — label for the assigned mbuzz specialist
- `accepted_at`, `kickoff_call_at`, `install_completed_at`, `integration_connected_at`, `training_call_at`, `value_check_at`, `completed_at` (datetimes)
- `notes` (text, nullable)
- `prefixed_ids` prefix `gst_`

Behaviour:
- Created `pending` when the offer is accepted (before payment).
- The `credit.purchase` webhook transitions `pending → in_progress` and stamps `accepted_at`.
- A specialist stamps milestone timestamps via the admin UI.
- Stamping `value_check_at` transitions `in_progress → delivered` and sets `completed_at`.
- Extract `GuidedSetup::Relationships` and `GuidedSetup::Scopes` (`in_progress`, `stalled` — in progress with no milestone stamped in 14 days) per house style.

### Admin

`Admin::GuidedSetupsController` — index (all engagements, `stalled` highlighted), show, update (stamp milestones, assign specialist, edit notes). Declares `skip_marketing_analytics` — it renders billing-adjacent customer data. Uses `find` with prefixed IDs.

### Booking

v1 uses an **external scheduling link** (Calendly or equivalent), a config value, surfaced in the customer welcome email and the offer confirmation. An embedded scheduler is out of scope.

### Emails (`GuidedSetupMailer`)

- `welcome` — to the customer: what to expect, the four touchpoints, the booking link.
- `internal_notification` — to the mbuzz team address (read from credentials/config — **no email address in git**, use a placeholder): a new engagement to staff.

---

## Onboarding Discovery Detail

### Placement

A new step **after persona, before SDK setup**, shown to **all personas** (marketers are strong concierge candidates, so they no longer skip straight to the dashboard).

Discovery is **not** a bitmask onboarding step — adding a bit mid-array would corrupt existing accounts' `onboarding_progress`. It is tracked by `setup_profile_completed_at`, and the controller routes on it. The 9-step bitmask is untouched.

### Schema (`accounts`)

- `setup_profile` (jsonb, default `{}`) — discovery answers. Validate `is_a?(Hash)` and the 50KB JSONB size limit per house rules.
- `setup_profile_completed_at` (datetime, nullable)

### The Five Questions

Each question must change what the account sees next.

| # | Question | Answers | Used for |
|---|----------|---------|----------|
| 1 | What are you trying to attribute? | ecommerce purchases / B2B leads & deals / signups & subscriptions / other | Conversion framing, fit score |
| 2 | Which ad platforms do you run? (multi-select) | Meta / Google Ads / TikTok / LinkedIn / none | Integration target, fit score |
| 3 | Do you use a CRM? | HubSpot / Salesforce / other / none | Fit score, specialist context |
| 4 | Roughly how much do you spend on ads per month? | <$5k / $5–25k / $25–100k / $100k+ | Fit score, plan recommendation |
| 5 | Who will do the install? | in-house developer / me (non-technical) / nobody yet | Strongest concierge signal |

Stored under stable keys in `setup_profile`: `attribution_goal`, `ad_platforms` (array), `crm`, `monthly_ad_spend`, `installer`.

### `Onboarding::FitScore`

A plain value object (an algorithm — does **not** inherit `ApplicationService`). `Onboarding::FitScore.new(setup_profile).call` returns `{ score:, eligible? }`.

| Signal | Points |
|--------|--------|
| `installer` = nobody yet | +40 |
| `installer` = me (non-technical) | +30 |
| `installer` = in-house developer | 0 |
| `monthly_ad_spend` = $100k+ | +35 |
| `monthly_ad_spend` = $25–100k | +30 |
| `monthly_ad_spend` = $5–25k | +15 |
| `monthly_ad_spend` = <$5k | 0 |
| `ad_platforms` count ≥ 3 | +20 |
| `ad_platforms` count = 2 | +12 |
| `crm` present (not "none") | +10 |
| `attribution_goal` = B2B leads & deals | +5 |

`eligible?` is `score >= GUIDED_SETUP_FIT_THRESHOLD` (constant, recommended **55**, tunable). The fit score gates the *concierge engagement* — that is where the ~$500 specialist cost sits, and the specialist team's time is finite. Given the acquisition priority, the threshold can be tuned **down** to widen the offer; it exists to keep the concierge queue manageable, not to protect margin.

Worked examples (at threshold 55): non-technical owner, $5–25k spend, 2 platforms, has a CRM → 30+15+12+10 = **67, eligible**. In-house developer, $25–100k, 3 platforms → 0+30+20 = **50, not eligible** (can self-serve). Non-technical owner, <$5k spend → 30, **not eligible**.

---

## Guided Setup Offer Detail

### The Offer Page (`/onboarding/guided_setup`)

Shown only to fit-eligible accounts:

- A short, risk-framed pitch: attribution is only as good as its install; DIY teams misattribute conversions for weeks. Guided Setup de-risks that.
- The offer: **$1,500 for hands-on Guided Setup — and the full $1,500 becomes credit on the plan you choose below.** Make the mechanics and the terms plain: the credit is applied to the selected plan now, cannot be saved for later, and is non-refundable.
- A **plan picker** — Starter / Growth / Pro — with the tier matching the account's `monthly_ad_spend` pre-selected and labelled "recommended."
- Two CTAs: **"Get Guided Setup"** (primary; disabled until a plan is chosen) and **"I'll set it up myself"** (continue self-serve).

### Accept / Decline / Purchase

- **Accept** (a plan is selected) → create `GuidedSetup` (`pending`, `integration_target` inferred from discovery answers), call `Billing::CreditCheckoutService` with the chosen plan, redirect to Stripe Checkout — **mode `payment`**, one $1,500 line item, metadata `guided_setup=true` and `plan_id`.
- **Decline** → record the decline on `setup_profile`, continue existing self-serve routing.
- On `checkout.session.completed` with **`mode == "payment"`** and the `guided_setup` metadata: `Billing::Handlers::CreditPurchaseCompleted` calls `Billing::GrantCreditService`, **starts the chosen plan's subscription** (the credit covers its invoices), transitions the `GuidedSetup` to `in_progress`, and fires `GuidedSetupMailer`. (The existing `checkout_completed` handler keeps owning `mode == "subscription"`; the webhook router branches on `session.mode`.)
- **Checkout abandoned** → `GuidedSetup` stays `pending`; no charge, no credit, no subscription; the offer re-shows.

### Second Surface: Billing Page

`accounts/billing/show.html.erb` shows the **current credit balance** for any account with credit, and a **Guided Setup offer card** for fit-eligible accounts that declined at onboarding or pre-date the feature. Eligibility reuses `Onboarding::FitScore` when a `setup_profile` exists.

---

## All States

| State | Condition | Expected Behaviour |
|-------|-----------|--------------------|
| Discovery not done | `setup_profile_completed_at` nil after persona | Route to `/onboarding/discovery` |
| Discovery done, eligible | `FitScore#eligible?` true | Route to `/onboarding/guided_setup` offer |
| Discovery done, not eligible | `FitScore#eligible?` false | Existing routing (marketer → dashboard, developer/both → setup) |
| Offer shown, no plan chosen | On the offer page | Primary CTA disabled until a plan is selected |
| Offer accepted | "Get Guided Setup" with a plan chosen | Create `GuidedSetup` pending; redirect to $1,500 Checkout |
| Offer declined | "I'll set it up myself" clicked | Record decline; continue self-serve |
| Checkout abandoned | Returns without paying | `GuidedSetup` stays `pending`; no charge/credit/subscription; offer re-shows |
| Payment completed | `checkout.session.completed`, `mode=payment` | Credit granted; chosen plan's subscription started; `GuidedSetup` → `in_progress`; emails sent |
| Credit drawing down | Active subscription invoices | Stripe applies the credit to each invoice automatically |
| Credit exhausted | Stripe credit balance hits zero | Normal monthly billing resumes on the card on file |
| Account cancelled with credit left | Subscription cancelled | Remaining credit forfeited; `AccountCredit` → `voided`; `GuidedSetup` → `cancelled` if not delivered |
| Engagement stalled | `in_progress`, no milestone in 14 days | Surfaced in the admin `stalled` scope for outreach |
| Engagement delivered | `value_check_at` stamped | `GuidedSetup` → `delivered`, `completed_at` set |
| Existing account, no profile | Pre-feature account visits billing | Generic offer card; no fit score |
| Marketer persona | persona = marketer | Now sees discovery before any dashboard redirect (intentional) |
| Empty discovery submit | Required answers missing | Re-render with validation errors; `setup_profile` unchanged |

---

## Implementation Tasks

### Phase 1: Account Credit

- [ ] **1.1** Migration: create `account_credits` (no expiry column)
- [ ] **1.2** `AccountCredit` model — `status` enum (`active`/`voided`), `cred_` prefix, scopes
- [ ] **1.3** `Account::Billing`: `has_many :account_credits`, `credit_balance_cents` (Stripe customer balance, cached)
- [ ] **1.4** `app/constants/billing.rb`: `GUIDED_SETUP_CREDIT_CENTS`
- [ ] **1.5** `Billing::GrantCreditService` — Stripe customer balance credit + `AccountCredit` row
- [ ] **1.6** Extend `Billing::Handlers::SubscriptionDeleted` — void the `AccountCredit` on cancellation
- [ ] **1.7** Write tests

### Phase 2: Guided Setup Engagement

- [ ] **2.1** Migration: create `guided_setups`
- [ ] **2.2** `GuidedSetup` model + `Relationships`/`Scopes` concerns; `status` enum; milestone methods; `gst_` prefix
- [ ] **2.3** `Account` `has_one :guided_setup`
- [ ] **2.4** `Admin::GuidedSetupsController` + index/show/update views — declare `skip_marketing_analytics`
- [ ] **2.5** Write tests

### Phase 3: Onboarding Discovery + Fit Score

- [ ] **3.1** Migration: add `setup_profile` jsonb + `setup_profile_completed_at` to `accounts`
- [ ] **3.2** `Account`: JSONB validation (`is_a?(Hash)`, 50KB limit)
- [ ] **3.3** `Onboarding::FitScore` value object + constants (`GUIDED_SETUP_FIT_THRESHOLD`, weights)
- [ ] **3.4** `OnboardingController#discovery` GET/POST + routes
- [ ] **3.5** `onboarding/discovery.html.erb` — 5-question form
- [ ] **3.6** Route persona completion → discovery for all personas
- [ ] **3.7** Write tests

### Phase 4: Offer + Credit Purchase

- [ ] **4.1** `OnboardingController#guided_setup` (offer + plan picker), `accept` (requires `plan_id`), `decline` + routes
- [ ] **4.2** `onboarding/guided_setup.html.erb` offer page — plan picker, recommended tier, terms line
- [ ] **4.3** `Billing::CreditCheckoutService` — one-time $1,500 Stripe Checkout (mode `payment`) carrying `guided_setup` + `plan_id` metadata
- [ ] **4.4** `Billing::Handlers::CreditPurchaseCompleted` — webhook router branches on `session.mode`; grant credit, start the chosen plan's subscription, transition `GuidedSetup`
- [ ] **4.5** `GuidedSetupMailer` — customer `welcome` (booking link), `internal_notification` (team address from credentials)
- [ ] **4.6** Audit `skip_marketing_analytics`: `OnboardingController` (renders plaintext API key) and `Accounts::BillingController`; add if missing
- [ ] **4.7** Write tests

### Phase 5: Credit Visibility + Billing Surface

- [ ] **5.1** Credit balance display on `accounts/billing/show.html.erb`
- [ ] **5.2** Guided Setup offer card on the billing page for non-onboarding accounts
- [ ] **5.3** Write tests

### Phase 6: Analytics & Docs

- [ ] **6.1** `Lifecycle::Tracker` events: `discovery_completed`, `guided_setup_offered`, `guided_setup_accepted`, `guided_setup_declined`, `credit_granted`
- [ ] **6.2** Admin metric: offer → accept conversion; activation within 30/60 days for Guided Setup accounts
- [ ] **6.3** Update `lib/docs/BUSINESS_RULES.md` section 9 (billing — credits) and `lib/docs/PRODUCT.md`
- [ ] **6.4** Move this spec to `lib/specs/old/` on completion

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Credit grant | `test/services/billing/grant_credit_service_test.rb` | Stripe balance credited $1,500; `AccountCredit` row `active`, `applied_plan_id` set |
| Credit checkout | `test/services/billing/credit_checkout_service_test.rb` | Session is `mode: payment`, $1,500, carries `guided_setup` + `plan_id` metadata |
| Webhook routing | `test/services/billing/handlers/credit_purchase_completed_test.rb` | `mode=payment` grants credit, starts the chosen subscription, transitions `GuidedSetup`; `mode=subscription` untouched |
| Credit voided on cancel | `test/services/billing/handlers/subscription_deleted_test.rb` | Cancellation marks the `AccountCredit` `voided`; no refund |
| Fit score | `test/services/onboarding/fit_score_test.rb` | Worked examples produce the expected `eligible?` |
| Engagement lifecycle | `test/models/guided_setup_test.rb` | Milestone stamps transition status; `value_check_at` → `delivered`; `stalled` scope |
| Discovery persistence | `test/controllers/onboarding_controller_test.rb` | `setup_profile` stored; required answers validated |
| Offer routing | `test/controllers/onboarding_controller_test.rb` | Eligible → offer; not eligible → existing routing; accept without a plan is rejected |
| Cross-account isolation | model + controller tests | An account cannot read another account's `GuidedSetup` or `AccountCredit` |

No mocks or stubs — test outcomes and business logic directly, per house style. Stripe is covered by the existing webhook-handler test approach.

### Manual QA (dev)

1. New signup → persona → discovery as a non-technical $25–100k advertiser → offer page shows the $1,500 copy and pre-selects the recommended tier.
2. Choose a plan, accept, complete Stripe test checkout (payment mode) → confirm the `AccountCredit` is granted, the Stripe customer balance is credited, the chosen plan's subscription is active, `GuidedSetup` is `in_progress`, both emails are sent.
3. Confirm the next plan invoice is fully covered by the credit.
4. New signup as an in-house developer, low spend → confirm the offer is skipped, self-serve routing intact.
5. Admin → open the engagement → stamp milestones through `value_check_at` → confirm `delivered` + `completed_at`.
6. Cancel a subscription with credit remaining → confirm the `AccountCredit` is `voided` and nothing is refunded.

---

## Definition of Done

- [ ] All tasks completed
- [ ] Tests pass (unit + controller + integration)
- [ ] Manual QA on dev
- [ ] No regressions in the existing onboarding funnel or billing webhooks
- [ ] `skip_marketing_analytics` verified on every controller touching billing, credits, or API keys
- [ ] No secrets or email addresses committed — credentials/placeholders only
- [ ] `BUSINESS_RULES.md` + `PRODUCT.md` updated
- [ ] Spec updated with final decisions and archived to `old/`

---

## Out of Scope

- **Annual billing** — explored and dropped from this offer; tracked separately in `lib/specs/future/annual_plans_spec.md`.
- **Building any new integration** — Guided Setup connects only integrations mbuzz already supports (Meta Ads, Google Ads, sGTM). A customer needing an integration mbuzz lacks is captured as product feedback, not delivered in the engagement.
- **Banked or transferable credit, credit expiry** — the credit is committed to a chosen plan at purchase; it cannot be held, moved, or expired.
- **Credit refunds** — the $1,500 and any unconsumed credit are non-refundable.
- **Variable credit amounts or multiple credit packs** — one $1,500 offer, one grant per account.
- **Promo / coupon codes** — no discount-code system.
- **Multi-currency** — credit and pricing are USD.
- **Embedded scheduling** — v1 uses an external booking link.
