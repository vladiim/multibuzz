# Guided Setup Service Specification

**Date:** 2026-05-19 (pivot 2026-05-21)
**Priority:** P1
**Status:** Phases 1–7 shipped on `feat/guided-setup-service`. Remaining: lifecycle events (6.7), billing surface card (6.8), admin conversion metric (6.9), `BUSINESS_RULES.md` / `PRODUCT.md` updates (6.10). Onboarding cohesion across all three branches tracked separately (see §"Onboarding cohesion follow-up" below).
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

**Visual + flow rules.** Every onboarding screen — across all three branches — conforms to `lib/docs/DESIGN_SYSTEM.md`. The unified onboarding chrome and the resume-nav pill are specified in §10 of that doc; the canonical wireframes are at `lib/mockups/onboarding-chrome.html`. The cohesion work that brings the existing screens onto the system is tracked in a follow-up spec; this Guided Setup spec assumes the system is in effect.

---

## Pivot — 2026-05-21

The customer no longer pays from a self-serve plan picker. A $1,500 done-for-you service does not convert from a button on a public-facing page. The new flow:

1. Customer chooses **"I'd like help"** → discovery → high-level offer page → **Book kickoff**. The customer captures scheduling preferences here, not after payment.
2. mbuzz runs the kickoff call. Specialist time is not yet committed.
3. Inside `Admin::GuidedSetupsController#show`, vlad clicks **"Generate payment link"** — mints a single-use, 48-hour token on the `GuidedSetup` row and surfaces the URL. Vlad sends it to the customer manually (email/Slack).
4. Customer clicks the link → token sign-in → lands on the **plan-picker page** → Stripe Checkout (mode `payment`, $1,500) → existing `Billing::Handlers::CreditPurchaseCompleted` webhook grants credit, starts the chosen subscription, transitions `GuidedSetup` to `in_progress`.
5. While the kickoff is booked but unpaid, an account-wide banner ("Complete your kickoff payment to begin") shows on every authenticated page.
6. vlad does not start delivery work until the credit is granted.

What's preserved from Phases 1–5: `AccountCredit`, `Billing::CreditCheckoutService`, `Billing::GrantCreditService`, `Billing::Handlers::CreditPurchaseCompleted`, `GuidedSetupMailer.welcome`/`internal_notification`, the discovery flow, `GuidedSetup` model + admin, `scheduling_preferences`. What changes: the customer-facing `guided_setup` view (no plan picker, "Book kickoff" CTA), `accept_guided_setup` is gated behind a token, scheduling preferences are captured on booking instead of on payment confirmation.

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

### Data Flow (shipped, post-pivot)

```
choose "I want mbuzz to do it"
  → accounts.setup_path = assisted
  → /onboarding/install_service       (overview + pricing mechanics)
  → /onboarding/discovery             (answers → accounts.setup_profile jsonb)
  → /onboarding/guided_setup          (book-kickoff form: scheduling_preferences)
  → POST /onboarding/book_kickoff
       → GuidedSetup created (pending) with kickoff_booked_at + scheduling_preferences
       → GuidedSetupMailer.kickoff_booked → internal_email
       → redirect to dashboard with notice
  → (specialist runs the kickoff call externally)
  → admin /admin/guided_setups/:id → "Generate payment link"
       → GuidedSetup.mint_payment_token! (48h single-use)
       → admin copies URL, sends to customer manually
  → /onboarding/payment/:token        (Onboarding::PaymentLinksController)
       → token validated, account owner signed in
       → redirect to /onboarding/payment_setup
  → /onboarding/payment_setup         (plan picker)
       → POST /onboarding/start_payment
       → Billing::CreditCheckoutService → Stripe Checkout
          (mode: payment, $1,500, success_url=…?session_id={CHECKOUT_SESSION_ID})
  → Stripe success_url → /onboarding/payment_complete?session_id=cs_xxx
       → Billing::VerifyCheckoutSessionService retrieves the session, confirms
         payment_status=paid + metadata.account_id matches, invokes the same
         CreditPurchaseCompleted handler the webhook would
       → handler is idempotent on AccountCredit; whichever lands first wins
  → checkout.session.completed (webhook, parallel path)
       → Billing::Handlers::CreditPurchaseCompleted
         → Billing::GrantCreditService (Stripe customer credit balance + AccountCredit row)
         → start the chosen plan's subscription
         → GuidedSetup → mark_paid! (status=in_progress, clears payment_token)
         → Turbo Stream broadcast → swaps processing state for success state
         → GuidedSetupMailer.welcome + .internal_notification
  → /onboarding/payment_complete      (success state; revisits → /dashboard)
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
| `app/services/billing/credit_checkout_service.rb` | One-time $1,500 Stripe Checkout; success URL templated with `?session_id={CHECKOUT_SESSION_ID}` |
| `app/services/billing/grant_credit_service.rb` | Stripe customer balance credit + ledger row |
| `app/services/billing/handlers/credit_purchase_completed.rb` | Webhook handler; idempotent on `AccountCredit` |
| `app/services/billing/verify_checkout_session_service.rb` | Success-URL Stripe session verifier; calls the handler synchronously (race + dev fallback) |
| `app/services/billing/handlers/subscription_deleted.rb` | Existing — void the credit on cancellation |
| `app/controllers/onboarding_controller.rb` | Setup-choice + entry routing |
| `app/controllers/concerns/onboarding/assisted_path.rb` | Discovery, install-service, guided_setup, book_kickoff |
| `app/controllers/concerns/onboarding/payment_flow.rb` | payment_setup, start_payment, payment_complete; skip-if-paid + active-token guards |
| `app/controllers/onboarding/payment_links_controller.rb` | Magic-link landing: validate token, sign in owner, redirect to payment_setup |
| `app/controllers/admin/guided_setups_controller.rb` | Manage engagements; "Generate payment link"; `skip_marketing_analytics` |
| `app/models/concerns/guided_setup/payment_journey.rb` | `book_kickoff!`, `mint_payment_token!`, `mark_paid!`, `awaiting_payment?`, `find_by_active_payment_token` |
| `app/mailers/guided_setup_mailer.rb` | Customer welcome + internal notification + kickoff_booked notification |
| `app/presenters/scheduling_preferences_presenter.rb` | View-facing wrapper around `scheduling_preferences` |
| `app/views/onboarding/show.html.erb` | Setup-choice screen (replaces persona) |
| `app/views/onboarding/install_service.html.erb` | Assisted-path overview + pricing mechanics |
| `app/views/onboarding/discovery.html.erb` | 4-question discovery form |
| `app/views/onboarding/guided_setup.html.erb` | Book-kickoff form (scheduling preferences) |
| `app/views/onboarding/payment_setup.html.erb` | Token-authed plan picker |
| `app/views/onboarding/payment_complete.html.erb` | Stripe success landing; processing / success states with Turbo Stream subscription |
| `app/constants/admin_tools.rb` | Registers the Guided Setups card on `/admin` |

---

## Account Credit Detail

The **Stripe customer credit balance** applies the credit automatically to **every** invoice mbuzz raises for that customer: subscription renewals, proration when the customer changes plan, one-off invoices, and metered/usage overages. Nothing in the codebase needs to opt invoices in. mbuzz keeps an **`account_credits` ledger** as the record of the grant for display and audit. The live remaining balance is the Stripe balance, shown on the billing page (cached ~5 min). There is **no expiry**: the credit sits on the customer balance and is drawn down by any mbuzz charge until it hits zero.

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
- `scheduling_preferences` (jsonb) — structured: `{ timezone, days[], time_blocks[] }`. Captured at booking, validated against `SchedulingPreferences` constants.
- `kickoff_booked_at` (datetime, nullable) — stamped by `book_kickoff!`; the customer is past the offer page.
- `payment_token` (string, nullable, partial unique index) + `payment_token_expires_at` (datetime, nullable) — single-use, 48h, minted by admin; cleared by `mark_paid!`.
- `accepted_at`, `kickoff_call_at`, `install_completed_at`, `integration_connected_at`, `training_call_at`, `value_check_at`, `completed_at` (datetimes)
- `notes` (text, nullable)
- `prefixed_ids` prefix `gst_`

Behaviour: created `pending` when the customer first books (`book_kickoff!` sets `kickoff_booked_at`). Admin mints a 48h `payment_token` after the kickoff call. On Stripe webhook OR success-URL verification, `mark_paid!` transitions to `in_progress`, stamps `accepted_at`, and clears the token in one transaction. A specialist stamps milestones via admin; stamping `value_check_at` moves it to `delivered` and sets `completed_at`. Concerns: `Relationships`, `Scopes` (`in_progress`, `stalled` = in progress, no milestone in 14 days), `Milestones`, `PaymentJourney`, `Recommendations`, `Validations`.

### Admin

`Admin::GuidedSetupsController` — index (`stalled` highlighted), show, update (stamp milestones, assign specialist, edit notes), `generate_payment_link` (mints a 48h token, surfaces the URL with a Copy button + Regenerate). Renders `scheduling_preferences` via `SchedulingPreferencesPresenter`. Declares `skip_marketing_analytics`. Uses `find` with prefixed IDs. Registered on the `/admin` hub via `AdminTools::ALL`.

### Booking & Emails

No scheduling tool. The book-kickoff form captures `scheduling_preferences` (timezone + days + time blocks); the specialist emails the customer to arrange the calls. `GuidedSetupMailer`:

- `kickoff_booked` — fires on booking → internal_email. Includes scheduling preferences, integration target, discovery answers.
- `welcome` — fires on payment landing → customer. The four touchpoints + what to expect.
- `internal_notification` — fires on payment landing → internal_email. Identifies the account, integration target, chosen plan.

Internal email address read from credentials; **no email address in git**.

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

## Book-first surface (post-pivot)

### Install service overview (`/onboarding/install_service`)

First screen on the assisted path. High-level explainer: four touchpoints, the **$1,500 → credit** mechanics, risk reversal ("Pay after the call", "No contract", "Non-refundable"). One primary CTA → discovery. No payment surface, no plan picker.

### Book Kickoff (`/onboarding/guided_setup`)

The customer captures scheduling preferences (timezone + preferred days + preferred time blocks) and clicks **Book now**. `book_kickoff` POST creates the `GuidedSetup` (if absent), stamps `kickoff_booked_at` + `scheduling_preferences`, and fires `GuidedSetupMailer.kickoff_booked` to ops. Customer is redirected to the dashboard. Revisits to this URL once booked → redirect to dashboard.

### Admin → Generate payment link

After the kickoff call, vlad opens the engagement at `/admin/guided_setups/:id` and clicks **Generate payment link**. `GuidedSetup#mint_payment_token!` mints a 48h URL-safe token; the admin page surfaces the full URL (`/onboarding/payment/:token`) in a copyable code block + a Regenerate button (rotates the token). Vlad sends the URL to the customer manually (email/Slack).

### Magic-link sign-in (`/onboarding/payment/:token`)

`Onboarding::PaymentLinksController#show`: looks up the engagement by `find_by_active_payment_token`, signs in `account.owner_user`, redirects to `/onboarding/payment_setup`. Invalid or expired token → redirect to login with an alert. Token is *not* cleared on click — the customer can re-open the link until the credit lands.

### Payment plan picker (`/onboarding/payment_setup`)

Token-authed plan picker. Three plan tiers; the tier matching `setup_profile.monthly_ad_spend` is pre-selected. **Pay $1,500** prominent CTA. `start_payment` POST invokes `Billing::CreditCheckoutService` and redirects to Stripe Checkout. Guards: `skip_if_already_paid` (in_progress → dashboard), `require_active_payment_link` (no token → onboarding with "expired link" alert).

### Payment complete (`/onboarding/payment_complete?session_id=cs_xxx`)

Stripe's `success_url`. Branches:

- **`current_account.guided_setup.in_progress?`** → success state (🎉 + "Go to dashboard").
- **Otherwise** → processing state (spinner + "Confirming your payment...") wrapped in a `turbo_frame_tag`.

Before rendering, the action calls `Billing::VerifyCheckoutSessionService` with the `session_id`. The service retrieves the Stripe session, verifies `payment_status=="paid"` and `metadata.account_id` matches, then invokes the same `CreditPurchaseCompleted` handler the webhook would. The handler is idempotent on `AccountCredit` — whichever path lands first wins; the other is a no-op.

When the webhook lands, `mark_paid!` runs and broadcasts a Turbo Stream replace targeting `payment_complete_state` on the `guided_setup_payment_<account>` channel. Customer's page swaps to the success state without reload.

### Abandonment

- Customer never gets the link from vlad → engagement stays `pending` with no token; admin can mint a fresh one anytime.
- Customer clicks the link but doesn't pay → token persists for 48h; they can re-click. Stripe's `cancel_url` returns them to `/onboarding/payment_setup`.
- Token expires before payment → admin regenerates from the admin show page.

---

## All States

| State | Condition | Behaviour |
|-------|-----------|-----------|
| Path not chosen | `setup_path` nil | Setup-choice screen |
| Path = self_serve | choice saved | Existing self-serve onboarding |
| Path = teammate | choice saved | `/onboarding/invite_teammate` |
| Path = assisted, discovery incomplete | `setup_profile_completed_at` nil | `/onboarding/install_service` → `/onboarding/discovery` |
| Path = assisted, discovery complete, not yet booked | `setup_profile_completed_at` set, `guided_setup&.kickoff_booked_at` nil | Book-kickoff form on `/onboarding/guided_setup` |
| Booked, awaiting payment link | `guided_setup.kickoff_booked_at` set, `payment_token` nil, status pending | Revisits to `/onboarding/guided_setup` → dashboard; admin generates the link when ready |
| Payment link active | `payment_token_active?` true, status pending | Customer clicks link → signed in → plan picker; the resume-nav pill (see `lib/docs/DESIGN_SYSTEM.md` §10) lands them here too |
| Payment landing (race window) | on `/onboarding/payment_complete?session_id=…`, status still pending | `VerifyCheckoutSessionService` runs synchronously; view shows processing state with Turbo subscription |
| Payment completed | webhook OR success-URL verifier finalised | `AccountCredit` granted, plan started, `GuidedSetup` → `in_progress`, token cleared, emails sent |
| Already paid, revisits payment surface | status `in_progress`, hits `payment_setup` or `start_payment` | `skip_if_already_paid` → dashboard |
| Token expired before payment | token cleared by TTL | Admin regenerates from `/admin/guided_setups/:id` |
| Credit drawing down | active subscription invoices | Stripe applies the credit automatically |
| Credit exhausted | Stripe credit balance hits zero | Normal monthly billing resumes on the card on file |
| Account cancelled with credit left | subscription cancelled | Remaining credit forfeited; `AccountCredit` → `voided`; `GuidedSetup` → `cancelled` if not delivered |
| Engagement stalled | `in_progress`, no milestone in 14 days | Surfaced in the admin `stalled` scope |
| Engagement delivered | `value_check_at` stamped | `GuidedSetup` → `delivered`, `completed_at` set |

---

## Implementation Tasks

### Phase 1: Account Credit ✅

- [x] **1.1** Migration: create `account_credits`
- [x] **1.2** `AccountCredit` model — `status` enum (`active`/`voided`), `cred_` prefix, scopes
- [x] **1.3** `Account::Billing`: `has_many :account_credits` (`credit_balance_cents` display helper folded into Phase 6)
- [x] **1.4** `app/constants/billing.rb`: `GUIDED_SETUP_CREDIT_CENTS`
- [x] **1.5** `Billing::GrantCreditService` — Stripe customer balance credit + `AccountCredit` row
- [x] **1.6** Extend `Billing::Handlers::SubscriptionDeleted` — void the credit on cancellation
- [x] **1.7** Tests

### Phase 2: Guided Setup Engagement ✅

- [x] **2.1** Migration: create `guided_setups` (incl. `scheduling_note`)
- [x] **2.2** `GuidedSetup` model + `Relationships`/`Scopes` concerns; `status` enum; milestone methods; `gst_` prefix
- [x] **2.3** `Account` `has_one :guided_setup`
- [x] **2.4** `Admin::GuidedSetupsController` + index/show/update views — declare `skip_marketing_analytics`
- [x] **2.5** Tests

### Phase 3: Setup-Choice Screen + Routing ✅

- [x] **3.1** Migration: add `setup_path` to `accounts`
- [x] **3.2** `Account`: `setup_path` enum
- [x] **3.3** `OnboardingController#show` renders the setup-choice screen; `#choose_path` (POST) stores `setup_path` and routes the three paths
- [x] **3.4** `onboarding/show.html.erb` → setup-choice screen; routes
- [x] **3.5** ~~Re-home demo data~~ — moot: no code gates demo data on `onboarding_persona`, so removing the persona screen broke nothing
- [x] **3.6** Tests

### Phase 4: Discovery ✅

- [x] **4.1** Migration: add `setup_profile` jsonb + `setup_profile_completed_at` to `accounts`
- [x] **4.2** `Account`: JSONB validation (`is_a?(Hash)`, 50KB limit)
- [x] **4.3** `OnboardingController#discovery` GET/POST — assisted path only; stores `setup_profile`
- [x] **4.4** `onboarding/discovery.html.erb` — 4 questions, each with an "Other" free-text
- [x] **4.5** Tests

### Phase 5: Guided Setup Page + Credit Purchase ✅

- [x] **5.1** `OnboardingController#guided_setup`, `accept_guided_setup` (requires `plan_slug`), `confirmation`, `submit_confirmation` + routes
- [x] **5.2** `onboarding/guided_setup.html.erb` + `confirmation.html.erb` (captures `scheduling_note`)
- [x] **5.3** `Billing::CreditCheckoutService` — $1,500 Stripe Checkout (mode `payment`), `guided_setup` + `plan_slug` metadata
- [x] **5.4** `Billing::Handlers::CreditPurchaseCompleted` — router branches on `session.mode`; grant credit, start the chosen plan's subscription, transition `GuidedSetup`
- [x] **5.5** `GuidedSetupMailer` — `welcome` (to customer), `internal_notification` (to internal_email from credentials)
- [x] **5.6** `skip_marketing_analytics` confirmed on `OnboardingController`, `Accounts::BillingController`, and `Admin::BaseController` (covers `Admin::GuidedSetupsController`)
- [x] **5.7** Tests — `OnboardingControllerTest` (assisted-path actions), `GuidedSetupMailerTest`, `CreditPurchaseCompletedTest` (mailer enqueuing), `PlanTest` + `GuidedSetupTest` (recommendation + integration-target helpers)

### Phase 6: Book-first pivot — capture-then-pay flow ✅ (6.1–6.5 shipped)

- [x] **6.1** Customer-side reframe: `guided_setup.html.erb` is the book-kickoff form. `book_kickoff` action stamps `kickoff_booked_at` + persists `scheduling_preferences`; status stays `pending`.
- [x] **6.2** Migration `20260521030000_add_payment_link_columns_to_guided_setups`: `payment_token` (partial unique index), `payment_token_expires_at`, `kickoff_booked_at`. `GuidedSetup::PaymentJourney` concern owns `book_kickoff!`, `mint_payment_token!`, `mark_paid!`, `awaiting_payment?`, `find_by_active_payment_token`.
- [x] **6.3** Admin "Generate payment link" button on `Admin::GuidedSetupsController#show`. URL surfaced in a copyable code block; Regenerate rotates the token.
- [x] **6.4** Magic-link landing: `Onboarding::PaymentLinksController#show` validates the token, signs in `account.owner_user`, redirects to `/onboarding/payment_setup`.
- [x] **6.5** Plan picker (`/onboarding/payment_setup`) + `start_payment` POST + `payment_complete` GET, all gated by `require_active_payment_link` and `skip_if_already_paid` in the `Onboarding::PaymentFlow` concern.
- [ ] **6.6** ~~Unpaid-kickoff banner~~ — **superseded** by the resume-nav pill specified in `lib/docs/DESIGN_SYSTEM.md` §10, landing in the onboarding cohesion follow-up.
- [ ] **6.7** `Lifecycle::Tracker` events: `setup_path_chosen` (shipped), `discovery_completed` (shipped), `kickoff_booked` (shipped), `payment_link_generated`, `credit_granted`.
- [ ] **6.8** Credit balance + Guided Setup status card on `accounts/billing/show.html.erb`.
- [ ] **6.9** Admin metric: booking → payment-link → purchase conversion; activation within 30/60 days.
- [ ] **6.10** Update `lib/docs/BUSINESS_RULES.md` (billing — credits) and `lib/docs/PRODUCT.md`.
- [ ] **6.11** Move this spec to `lib/specs/old/` on completion.

### Phase 7: Hardening ✅

- [x] **7.1** `Billing::CreditCheckoutService` templates `?session_id={CHECKOUT_SESSION_ID}` into the success URL.
- [x] **7.2** `Billing::VerifyCheckoutSessionService` retrieves the Stripe session on the success URL, confirms `payment_status=paid` and `metadata.account_id` matches, invokes the webhook handler synchronously. Handler stays idempotent on `AccountCredit`; whichever path lands first wins. Independent of webhook delivery — fixes local dev (no Stripe CLI listener needed) and the production race window.
- [x] **7.3** `payment_complete` view branches on `in_progress?`: success state or Turbo-subscribed processing state. Webhook broadcasts `payment_complete_state` replace to `guided_setup_payment_<account>` so the page swaps live.
- [x] **7.4** `skip_if_already_paid` before_action on `payment_setup` and `start_payment` — once paid, both surfaces redirect straight to dashboard.
- [x] **7.5** Admin Guided Setups card registered in `AdminTools::ALL` (and CLAUDE.md rule added: every new admin surface must register).
- [x] **7.6** Admin form inputs adopt the visible-border baseline (`lib/memory/feedback_visible_form_inputs.md`).
- [x] **7.7** `SchedulingPreferencesPresenter` extracts view-side hash munging; admin show and `kickoff_booked` confirmation consume it.

### Phase 8: Onboarding cohesion (follow-up spec)

Tracked separately. See `lib/docs/DESIGN_SYSTEM.md` §10 (chrome + resume nav) and the §"Onboarding cohesion follow-up" pointer below.

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

1. New signup → setup-choice → "I want mbuzz to do it" → install-service overview → discovery → Book-kickoff form (timezone + days + times) → submits → redirected to dashboard with notice. `kickoff_booked` mailer enqueued.
2. Admin → `/admin/guided_setups/:id` → "Generate payment link" → URL appears with Copy + Regenerate. Open URL in a fresh incognito window (or as a different user).
3. Magic-link lands the customer on `/onboarding/payment_setup` (signed in as the account owner). Plan picker shows recommended tier pre-selected.
4. Choose plan → Pay → Stripe test checkout (mode `payment`) → success → land on `/onboarding/payment_complete?session_id=cs_xxx`.
5. Verify either path lands the engagement: with `stripe listen` running, the webhook finalises and the Turbo broadcast swaps the page to success. Without `stripe listen`, the `VerifyCheckoutSessionService` finalises synchronously on the success URL.
6. Reload `/onboarding/payment_setup` after payment → redirect to dashboard (skip-if-paid).
7. Admin → stamp milestones through `value_check_at` → `delivered` + `completed_at`.
8. Cancel a subscription with credit remaining → `AccountCredit` `voided`, nothing refunded.
9. New signup → "My teammate will" → lands in the in-onboarding invite step; send invite → "Invite sent" state.
10. New signup → "I'll do it" → existing self-serve onboarding, unchanged.

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
- **Scheduling tool integration** — the specialist arranges calls by email; only structured `scheduling_preferences` are captured.
- **Promo / coupon codes; multi-currency** — credit and pricing are USD.

---

## Onboarding cohesion follow-up

The 2026-05 onboarding cohesion audit (see `lib/docs/DESIGN_SYSTEM.md`) identified drift across all three branches: container widths, typography, escape hatches, status idioms, the "Step X of 5" lie, no reentry surface for partially-onboarded accounts, branch-unaware `current_onboarding_step`. Resolving it is a separate work stream:

- Unified onboarding chrome (top bar + pip rail + exit) wrapping every screen — wireframes at `lib/mockups/onboarding-chrome.html`.
- Branch-aware `Account#onboarding_step` + `Account#onboarding_resume_path` resolver.
- Resume-nav pill in the main app top nav, replacing the obsolete `_onboarding_banner` and the deferred Phase 6.6 unpaid-kickoff banner.
- Shared `_waiting_state` and `_success_state` partials, factoring out the duplicated spinner + emoji-hero markup.
- Per-screen migration to the system documented in `lib/docs/DESIGN_SYSTEM.md`.

Tracked in a follow-up spec (TBD: `lib/specs/onboarding_cohesion_spec.md`).
