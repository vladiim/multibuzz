# Customer Lifecycle Tracking Specification

**Date:** 2026-04-22
**Priority:** P1
**Status:** Ready
**Branch:** `feature/session-bot-detection`

---

## Summary

We have zero visibility into what customers do between signup and payment (or churn). We dogfood Mbuzz for `signup`, `login`, `first_test_event`, `first_production_event`, and `payment` -- but the entire middle of the funnel is dark. We can't answer: how many accounts finish onboarding? How many send production data? How many hit the free limit and upgrade vs churn? This spec adds server-side lifecycle events via our existing Mbuzz dogfooding so we can see the full journey from signup to revenue (or death).

---

## Current State

### What We Track Today

| Event | Type | Where | File |
|-------|------|-------|------|
| `signup` | conversion | Signup controller | `app/controllers/signup_controller.rb:41` |
| `login` | event | Sessions controller | `app/controllers/sessions_controller.rb:39` |
| `first_test_event` | event | Event broadcast | `app/models/concerns/event/broadcasts.rb:43` |
| `first_production_event` | event | Event broadcast | `app/models/concerns/event/broadcasts.rb:43` |
| `payment` | conversion | Invoice paid handler | `app/services/billing/handlers/invoice_paid.rb:37-44` |

### What's Dark

- Entire onboarding funnel (persona, SDK choice, install, verify, conversion, attribution, complete, skip)
- Usage milestones (25%, 50%, 80%, 100% of free limit)
- Plan upgrade / downgrade
- Subscription cancellation
- Payment failure / recovery
- Feature adoption (ad platforms, custom models, CSV exports)
- Time-to-value metrics (signup → first event, signup → first conversion, signup → activation)

### Mbuzz Dogfooding Infrastructure

Already initialized in `config/initializers/mbuzz.rb` using `Mbuzz.init(api_key: credentials.dig(:mbuzz, :api_token))`. Server-side Ruby SDK is proven -- we call `Mbuzz.event`, `Mbuzz.conversion`, and `Mbuzz.identify` from controllers and services today.

---

## Proposed Solution

Extend the existing Mbuzz dogfooding. No Ahoy, no new gem, no new tables.

**Why not Ahoy?** Ahoy is a client-side-first gem that creates its own visits/events tables, its own visitor tracking cookies, and its own session model. We already have all of that -- we *are* an analytics product. Adding Ahoy would mean running a second analytics system inside our analytics system. Instead, we dogfood our own SDK, which gives us real data in our own dashboard and validates our own product.

**Why not a custom `lifecycle_events` table?** Same reason. We have an events table, an SDK, and a dashboard. Use them. If we can't answer lifecycle questions with our own product, that's a product bug, not a tracking gap.

### Approach

1. Create a `Lifecycle::Tracker` module -- thin wrapper around `Mbuzz.event` / `Mbuzz.conversion` that resolves the account owner and adds standard properties (account_id, plan, billing_status, usage_percentage)
2. Instrument lifecycle moments by calling `Lifecycle::Tracker` from existing code paths (controllers, services, concerns)
3. Properties on every lifecycle event enable segmentation: plan, billing status, usage %, days since signup, onboarding %

### Data Flow

```
User action (e.g. completes onboarding step)
  → Existing code path (e.g. Account::Onboarding#complete_onboarding_step!)
    → Lifecycle::Tracker.track("onboarding_step_completed", account, step: :sdk_selected)
      → Mbuzz.event("onboarding_step_completed", user_id: owner.prefix_id, ...)
        → POST /api/v1/events (to our own mbuzz account)
          → Visible in our own dashboard
```

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Tracking system | Mbuzz dogfooding (extend existing) | We ARE an analytics product. Dogfood it. Validates our own SDK, gives us data in our own dashboard. |
| New gem/table | No | Ahoy adds redundant infra. Custom table adds a second system. Use what we have. |
| Wrapper module | `Lifecycle::Tracker` | Centralizes owner resolution, standard properties, and guards (skip if no owner, skip in test env). Single place to change if we add more context later. |
| Event naming | `snake_case` with domain prefix (e.g. `onboarding_completed`, `billing_upgraded`) | Matches our existing `first_test_event`, `payment` conventions. Grep-friendly. |
| Sensitive data | Never send email, API keys, or PII in properties | Properties go through our own pipeline but principle stands. Send `account_id` (prefix_id), `plan`, `billing_status` -- never raw emails or keys. |
| Fire-and-forget | Yes -- lifecycle tracking must never block or raise | Wrap in `rescue nil` at the Tracker level. Tracking failure must not break the product. |

---

## Lifecycle Events

### Signup & Onboarding

| Event | Type | Trigger Point | Key Properties |
|-------|------|---------------|----------------|
| `signup` | conversion | `SignupController#create` | **Already tracked.** No change. |
| `onboarding_persona_selected` | event | `OnboardingController#persona` | `persona` (developer/marketer/both) |
| `onboarding_sdk_selected` | event | `OnboardingController#select_sdk` | `sdk_key` |
| `onboarding_first_event` | event | `Account::Onboarding#complete_onboarding_step!(:first_event_received)` | `is_test`, `days_since_signup` |
| `onboarding_first_conversion` | event | `Account::Onboarding#complete_onboarding_step!(:first_conversion)` | `days_since_signup` |
| `onboarding_activated` | event | `Account::Onboarding#set_activation_timestamp!` | `days_since_signup` |
| `onboarding_completed` | event | `Account::Onboarding#set_completion_timestamp!` | `days_since_signup`, `onboarding_percentage` |
| `onboarding_skipped` | event | `OnboardingController#skip` | `onboarding_percentage`, `current_step` |

### Data Ingestion Milestones

| Event | Type | Trigger Point | Key Properties |
|-------|------|---------------|----------------|
| `first_test_event` | event | `Event::Broadcasts` | **Already tracked.** No change. |
| `first_production_event` | event | `Event::Broadcasts` | **Already tracked.** No change. |
| `usage_milestone` | event | `Account::Billing#increment_usage!` | `milestone` (25/50/80/100), `plan`, `usage_count`, `limit` |

Usage milestones fire once per billing period per threshold. Track via cache key: `account:{id}:milestone:{period}:{pct}` where `period` is `Account#current_billing_period` (already exists at `app/models/concerns/account/billing.rb:87`, returns `"YYYY-MM"`). Cache TTL: 45 days (covers a full billing period plus buffer; Solid Cache honours `expires_in`).

### Billing & Payments

| Event | Type | Trigger Point | Key Properties |
|-------|------|---------------|----------------|
| `payment` | conversion | `Billing::Handlers::InvoicePaid` | **Already tracked.** Now also increments denormalized `accounts.lifetime_value_cents`. |
| `billing_upgraded` | event | `Billing::Handlers::CheckoutCompleted` | `plan`, `from_plan`, `days_since_signup` |
| `billing_trial_started` | event | `Account::Billing#start_trial!` | `plan`, `trial_ends_at` |
| `billing_trial_expired` | event | `Billing::ExpireFreeUntilService` (or trial expiry job) | `plan`, `days_on_trial` |
| `billing_payment_failed` | event | `Billing::Handlers::InvoicePaymentFailed` | `plan`, `grace_period_ends_at` |
| `billing_payment_recovered` | event | `Billing::Handlers::InvoicePaid` (when clearing past_due) | `plan`, `days_past_due` |
| `billing_cancelled` | event | `Billing::Handlers::SubscriptionDeleted` | `plan`, `days_as_customer`, `lifetime_value` |
| `billing_reactivated` | event | `Account::Billing#restore_from_past_due!` or reactivation | `plan`, `days_inactive` |

**LTV denormalization.** `accounts.lifetime_value_cents` (bigint, default 0) is incremented in `Billing::Handlers::InvoicePaid` by `event_object[:amount_paid]` before `track_payment` fires. This keeps the customer metrics report cheap (no JSONB scan) and gives `billing_cancelled` a reliable `lifetime_value` property. Source of truth stays in Stripe; we denormalize for our own reporting.

### Feature Adoption

| Event | Type | Trigger Point | Key Properties |
|-------|------|---------------|----------------|
| `feature_ad_platform_connected` | event | `AdPlatforms::Google::AcceptConnectionService` (and future platforms) | `platform`, `connections_used`, `connection_limit` |
| `feature_custom_model_created` | event | Attribution model creation service | `model_count`, `model_limit` |
| `feature_csv_exported` | event | `Dashboard::CsvExportService` | `export_type` |

---

## `Lifecycle::Tracker` Module

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/services/lifecycle/tracker.rb` | New. Central tracking module. | Create |
| `app/models/concerns/account/onboarding.rb` | Onboarding steps | Add tracking calls |
| `app/models/concerns/account/billing.rb` | Billing actions | Add tracking calls to `increment_usage!` |
| `app/controllers/onboarding_controller.rb` | Onboarding UI | Add tracking calls |
| `app/services/billing/handlers/checkout_completed.rb` | Upgrade | Add tracking call |
| `app/services/billing/handlers/invoice_paid.rb` | Payment recovery | Add tracking call (already has payment) |
| `app/services/billing/handlers/invoice_payment_failed.rb` | Payment failure | Add tracking call |
| `app/services/billing/handlers/subscription_deleted.rb` | Cancellation | Add tracking call |

### Interface

```ruby
# app/services/lifecycle/tracker.rb
module Lifecycle
  module Tracker
    module_function

    def track(event_name, account, **properties)
      return if Rails.env.test?

      owner = resolve_owner(account)
      return unless owner

      Mbuzz.event(
        event_name,
        user_id: owner.prefix_id,
        **standard_properties(account),
        **properties
      )
    rescue StandardError
      # Fire-and-forget. Never break the product for tracking.
      nil
    end

    def resolve_owner(account)
      account.account_memberships.owner.accepted.first&.user
    end

    def standard_properties(account)
      {
        account_id: account.prefix_id,
        account_name: account.name,
        plan: account.plan&.slug || "free",
        billing_status: account.billing_status,
        days_since_signup: ((Time.current - account.created_at) / 1.day).round,
        usage_percentage: account.usage_percentage
      }
    end
  end
end
```

### Usage Milestone Tracking

```ruby
# Inside Account::Billing#increment_usage!
def increment_usage!(count = 1)
  Rails.cache.increment(usage_cache_key, count)
  check_usage_milestones!
end

USAGE_MILESTONES = [25, 50, 80, 100].freeze

def check_usage_milestones!
  pct = usage_percentage
  USAGE_MILESTONES.each do |milestone|
    next if pct < milestone

    milestone_key = "account:#{id}:milestone:#{current_billing_period}:#{milestone}"
    next if Rails.cache.read(milestone_key)

    Rails.cache.write(milestone_key, true, expires_in: 45.days)
    Lifecycle::Tracker.track("usage_milestone", self, milestone: milestone, usage_count: current_period_usage, limit: free_event_limit)
  end
end
```

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path | Signup → onboard → send data → upgrade → pay | Full funnel of events from `signup` through `billing_upgraded` and `payment` |
| Skip onboarding | User clicks skip | `onboarding_skipped` fires with current progress |
| Marketer persona | Selects marketer | `onboarding_persona_selected` with `persona: "marketer"`, then redirect (no SDK steps) |
| Hit free limit | 30K events reached | `usage_milestone` at 80% and 100%, then billing banner |
| Upgrade from free | Checkout → active | `billing_upgraded` with `from_plan: "free"`, then `payment` on first invoice |
| Payment fails | Stripe invoice.payment_failed | `billing_payment_failed` fires |
| Payment recovers | Stripe invoice.paid while past_due | `billing_payment_recovered` fires, then `payment` conversion |
| Cancellation | Stripe subscription.deleted | `billing_cancelled` with tenure data |
| No owner | Account with no accepted owner membership | Tracker silently skips (returns nil) |
| Test environment | `Rails.env.test?` | All tracking silently skipped |
| Mbuzz SDK failure | API key invalid, network error, etc. | Rescued, returns nil, product unaffected |

---

## Implementation Tasks

### Phase 1: Tracker Module + Onboarding Events

- [ ] **1.1** Create `app/services/lifecycle/tracker.rb` with `track`, `resolve_owner`, `standard_properties`
- [ ] **1.2** Add `onboarding_persona_selected` to `OnboardingController#persona`
- [ ] **1.3** Add `onboarding_sdk_selected` to `OnboardingController#select_sdk`
- [ ] **1.4** Add `onboarding_activated` to `Account::Onboarding#set_activation_timestamp!`
- [ ] **1.5** Add `onboarding_completed` to `Account::Onboarding#set_completion_timestamp!`
- [ ] **1.6** Add `onboarding_skipped` to `OnboardingController#skip`
- [ ] **1.7** Write tests for `Lifecycle::Tracker` (mocks Mbuzz.event, verifies properties)

### Phase 2: Usage Milestones

- [ ] **2.1** Add `check_usage_milestones!` to `Account::Billing#increment_usage!`
- [ ] **2.2** Add `USAGE_MILESTONES` constant
- [ ] **2.3** Write tests for milestone deduplication (fires once per period per threshold)

### Phase 3: Billing Events

- [ ] **3.1** Add `billing_upgraded` to `Billing::Handlers::CheckoutCompleted`
- [ ] **3.2** Add `billing_trial_started` to `Account::Billing#start_trial!`
- [ ] **3.3** Add `billing_payment_failed` to `Billing::Handlers::InvoicePaymentFailed`
- [ ] **3.4** Add `billing_payment_recovered` to `Billing::Handlers::InvoicePaid#clear_past_due_status`
- [ ] **3.5** Add `billing_cancelled` to `Billing::Handlers::SubscriptionDeleted`
- [ ] **3.6** Write tests for billing lifecycle events

### Phase 4: Feature Adoption

- [ ] **4.1** Add `feature_ad_platform_connected` to `AdPlatforms::Google::AcceptConnectionService`
- [ ] **4.2** Add `feature_custom_model_created` to attribution model creation (skip if no service exists yet — note in spec)
- [ ] **4.3** Add `feature_csv_exported` to `Dashboard::CsvExportService`
- [ ] **4.4** Write tests for feature adoption events

### Phase 5: Internal Signup Notification Email

When a new account signs up, send an internal notification to the recipient configured in `Rails.application.credentials.dig(:internal_notifications, :signup_recipient)`. Recipient is **never** hardcoded (per CLAUDE.md secret-handling rules).

- [ ] **5.1** Add `:internal_notifications` namespace to Rails credentials with `signup_recipient` (set on each environment, not committed)
- [ ] **5.2** Create `app/mailers/internal_notifications_mailer.rb` with `new_signup(account_id)` action
- [ ] **5.3** Create `app/views/internal_notifications_mailer/new_signup.html.erb` and `.text.erb`
- [ ] **5.4** Create `app/services/internal_notifications/signup_stats_service.rb` (returns `{ total_accounts:, signups_today:, signups_this_week:, signups_this_month:, trial_to_paid_rate_30d: }` — query object, not ApplicationService)
- [ ] **5.5** Create `app/jobs/internal_notifications/new_signup_job.rb` — thin one-line `deliver_now` wrapper
- [ ] **5.6** Trigger from `SignupController#create` after the existing `Mbuzz.conversion("signup", ...)` line via `perform_later`
- [ ] **5.7** Skip in test env (or use test mailer queue); skip if recipient not configured (return nil)
- [ ] **5.8** Tests: mailer test (renders, addresses correct recipient), service test (counts accurate), controller test (job enqueued on signup)

**Email contents:**

| Section | Fields |
|---------|--------|
| Header | `New mbuzz signup: {account.name}` |
| Account | name, prefix_id, slug, plan name, owner name (no raw email body — owner name only), persona if set, selected SDK if set |
| Acquisition | UTM source/medium/campaign/content/term, referrer, country (from owner's most recent visitor session if available) |
| Funnel context | total accounts (all-time), signups today, signups this week, signups this month, 30-day signup→paid conversion rate |

**Why a service for stats?** Keeps the mailer thin (per CLAUDE.md). Stats query is reusable later (e.g. weekly digest email, admin dashboard tile).

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Tracker skips in test env | `test/services/lifecycle/tracker_test.rb` | Returns nil when `Rails.env.test?` (override for test) |
| Tracker resolves owner | `test/services/lifecycle/tracker_test.rb` | Finds accepted owner membership |
| Tracker skips without owner | `test/services/lifecycle/tracker_test.rb` | Returns nil for ownerless accounts |
| Tracker rescues errors | `test/services/lifecycle/tracker_test.rb` | StandardError doesn't propagate |
| Standard properties correct | `test/services/lifecycle/tracker_test.rb` | Includes account_id, plan, billing_status, days_since_signup |
| Usage milestones deduplicate | `test/models/concerns/account/billing_test.rb` | Same milestone doesn't fire twice in same period |
| Usage milestones fire at thresholds | `test/models/concerns/account/billing_test.rb` | 25%, 50%, 80%, 100% each trigger once |

### Testing Approach

Since `Lifecycle::Tracker` skips in test env by default, tests must stub `Rails.env.test?` to return false (or extract the guard to a method and stub that). Then assert `Mbuzz.event` receives the correct arguments.

```ruby
test "tracks onboarding_completed with correct properties" do
  Lifecycle::Tracker.stub(:skip_tracking?, false) do
    mock = Minitest::Mock.new
    mock.expect(:call, nil, ["onboarding_completed"], user_id: owner.prefix_id, account_id: account.prefix_id, **anything)

    Mbuzz.stub(:event, mock) do
      account.complete_onboarding_step!(:onboarding_complete)
    end

    mock.verify
  end
end
```

---

## Sensitive Routes

`Lifecycle::Tracker` runs server-side only (no new controllers, no new routes). No new pages are rendered. All existing controllers that get tracking calls already have appropriate `skip_marketing_analytics` declarations where needed. No changes required.

---

## Definition of Done

- [ ] `Lifecycle::Tracker` module exists with fire-and-forget semantics
- [ ] All onboarding steps emit events
- [ ] Usage milestones fire at 25/50/80/100% (deduplicated per period)
- [ ] Billing transitions (upgrade, cancel, payment fail/recover) emit events
- [ ] Feature adoption events fire for ad platforms, custom models, CSV exports
- [ ] `accounts.lifetime_value_cents` denormalized counter ticks on every paid invoice
- [ ] Internal signup notification email delivered to the configured recipient on every new account
- [ ] All tests pass (unit + full suite)
- [ ] No existing behavior changed -- tracking is additive only
- [ ] Spec updated with final state

---

## Out of Scope

- Client-side tracking (GTM, GA4 already handles marketing pages)
- Cohort analysis dashboards (use the data in our own dashboard first)
- Automated churn prediction / alerts (future: build on this data)
- Email campaign triggers based on lifecycle events (future)
- Revenue attribution back to acquisition channel for our own signups (we already track `signup` as a conversion with `is_acquisition: true` -- attribution is automatic)
