# Billing Implementation Specification

**Status**: In Progress (Phase 4 Complete)
**Priority**: P0 (Required for launch)
**Last Updated**: 2025-12-03

---

## Executive Summary

Complete billing system using Stripe for payment processing, Postmark for transactional emails, with metered billing, free tier support, and admin analytics.

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Payment Processor | **Stripe** | Industry standard, Checkout + Portal + Meters |
| Email Service | **Postmark** | Best deliverability, transactional focus |
| Banking | **CBA business account** | Stripe pays out in AUD directly |
| Airwallex | **Not needed** | Stripe handles FX for international customers |
| Card Collection | **Stripe Checkout** | PCI compliant, Apple/Google Pay built-in |
| Self-Service | **Stripe Customer Portal** | Zero UI to build for card updates, cancellations |
| Usage Counter | **Solid Cache** | Consistent with Solid Stack, no Redis needed |
| Past Due Events | **Store locked, unlock on payment** | No data loss, incentivizes payment |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              Customer Flow                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   [Signup] → [Free Forever / Free Until / Trial] → [Checkout] → [Paid] │
│                                                                          │
│   [Settings] → [Manage Subscription] → [Stripe Customer Portal]         │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                              Backend Flow                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   [Event Ingestion] → [Usage Counter (Solid Cache)] → [Limit Check]    │
│                                    ↓                                     │
│                     [Stripe Meter Events via Solid Queue]               │
│                                                                          │
│   [Stripe Webhooks] → [Webhook Handlers] → [Update Account Status]     │
│                                ↓                                         │
│                        [Postmark Emails]                                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Account Billing States

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ free_forever │     │  free_until  │     │   trialing   │
└──────────────┘     └──────────────┘     └──────────────┘
                            │                    │
                            ▼                    ▼
                     ┌──────────────┐     ┌──────────────┐
                     │   expired    │◀────│    active    │
                     └──────────────┘     └──────────────┘
                                                │
                                                ▼
                                         ┌──────────────┐
                                         │   past_due   │
                                         └──────────────┘
                                                │
                                                ▼
                                         ┌──────────────┐
                                         │  cancelled   │
                                         └──────────────┘
```

| State | Description | Can Ingest? | Events Visible? |
|-------|-------------|-------------|-----------------|
| `free_forever` | No payment required, 10K hard cap | Until limit | Yes |
| `free_until` | Admin-granted free access until date | Yes | Yes |
| `trialing` | Trial period with plan features | Yes | Yes |
| `active` | Paid subscription current | Yes | Yes |
| `past_due` | Payment failed, in grace period | Yes (locked) | Locked events hidden |
| `cancelled` | Subscription ended | No | Yes (historical) |
| `expired` | Trial/free_until ended | No | Yes (historical) |

### Free Until (Friends & Early Users)

Special state for granting extended free access:
- Admin sets `free_until` date via admin panel
- Full access to specified plan until date
- No payment method required
- On expiry: transitions to `expired` (prompt to subscribe)
- Can be extended by admin at any time

Use cases:
- Beta testers
- Friends & family
- Strategic partners
- Competition winners

### Past Due Behavior (Store & Lock)

When payment fails:
1. **Grace period**: 3 days of normal operation
2. **After grace**: Events still stored but marked `locked: true`
3. **Dashboard**: Big warning banner, locked events hidden from queries
4. **Attribution**: Locked events excluded from attribution calculations
5. **On payment**: All locked events unlocked, attribution recalculated
6. **After 30 days**: Stop storing entirely, account suspended

```
Payment Failed
     │
     ▼ (3 days grace)
Store events normally
     │
     ▼ (day 4-30)
Store events with locked: true
Show dashboard warning
     │
     ▼ (day 31+)
Stop storing, suspend account
```

---

## Pricing Plans

| Plan | Monthly | Events Included | Overage (per 10K) |
|------|---------|-----------------|-------------------|
| Free | $0 | 10,000 | N/A (hard cap) |
| Starter | $29 | 50,000 | $5.80 |
| Growth | $99 | 250,000 | $3.96 |
| Pro | $299 | 1,000,000 | $2.99 |
| Enterprise | Custom | Custom | Custom |

### Free Forever
- Default for all new signups
- No credit card required
- Hard cap at 10K events (rejected after)
- Full dashboard access
- Upgrade prompts at 80% and 100%

### Free Until (Admin Granted)
- Set via admin panel
- Full plan access until specified date
- No event limits (uses plan limits)
- Reminder emails before expiry
- Transitions to expired on date

### Trial Accounts
- Created when user adds payment method
- Configurable duration (default 14 days)
- Full access to selected plan
- Auto-converts to paid at trial end
- Auto-expires if payment fails

---

## Dashboard Warnings

### Past Due Banner
```
┌─────────────────────────────────────────────────────────────────────────┐
│ ⚠️  PAYMENT FAILED                                                      │
│                                                                          │
│ Your payment failed on Nov 28. Events are being stored but locked.     │
│ Update your payment method to unlock your data and continue tracking.  │
│                                                                          │
│ [Update Payment Method]                              [Contact Support]  │
└─────────────────────────────────────────────────────────────────────────┘
```

### Free Until Expiring Banner
```
┌─────────────────────────────────────────────────────────────────────────┐
│ ℹ️  FREE ACCESS ENDING                                                  │
│                                                                          │
│ Your free access expires in 5 days. Subscribe to continue tracking.    │
│                                                                          │
│ [View Plans]                                                            │
└─────────────────────────────────────────────────────────────────────────┘
```

### Usage Limit Banner (Free Tier)
```
┌─────────────────────────────────────────────────────────────────────────┐
│ ⚠️  EVENT LIMIT REACHED                                                 │
│                                                                          │
│ You've used 10,000 of 10,000 events this month.                        │
│ New events are not being tracked. Upgrade to continue.                 │
│                                                                          │
│ [Upgrade Now]                                                           │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Stripe Components

| Component | Purpose |
|-----------|---------|
| **Checkout Sessions** | Collect payment (cards, Apple Pay, Google Pay) |
| **Customer Portal** | Self-service subscription management |
| **Subscriptions** | Recurring billing lifecycle |
| **Meters** (2024) | Usage-based billing tracking |
| **Webhooks** | Real-time event notifications |

### Stripe Products Setup

```
Stripe Dashboard Products:
├── mbuzz Starter
│   ├── Base price: $29/month (recurring)
│   └── Metered price: $5.80 per 10K events (usage-based)
├── mbuzz Growth
│   ├── Base price: $99/month
│   └── Metered price: $3.96 per 10K events
└── mbuzz Pro
    ├── Base price: $299/month
    └── Metered price: $2.99 per 10K events
```

---

## Email Service (Postmark)

### Why Postmark
- 22% better inbox placement than SendGrid
- Focused on transactional (not marketing)
- 45 days message history included
- Simple API, excellent Rails support

### Emails to Send

| Trigger | Email | Priority |
|---------|-------|----------|
| Account created | Welcome | P0 |
| Free until granted | Free access confirmation | P0 |
| Free until ending (7 days) | Expiry reminder | P0 |
| Free until ending (1 day) | Final reminder | P0 |
| Free until expired | Access ended, subscribe CTA | P0 |
| Trial starting | Trial welcome | P0 |
| Trial ending (3 days) | Trial reminder | P0 |
| Trial expired | Expired, upgrade CTA | P0 |
| Subscription created | Payment confirmation | P0 |
| Payment failed | Update card CTA | P0 |
| Payment failed (day 4) | Events now locked warning | P0 |
| Payment succeeded (after failure) | Service restored, events unlocked | P0 |
| Usage at 80% | Approaching limit | P1 |
| Usage at 100% | Limit reached | P0 |
| Overage charged | Overage receipt | P1 |
| Subscription cancelled | Cancellation confirmation | P0 |

---

## Webhook Events

### Must Handle

| Event | Action |
|-------|--------|
| `checkout.session.completed` | Link subscription to account, activate |
| `customer.subscription.created` | Record subscription details |
| `customer.subscription.updated` | Sync plan changes, period dates |
| `customer.subscription.deleted` | Mark cancelled |
| `customer.subscription.trial_will_end` | Send trial ending email |
| `invoice.paid` | Clear past_due, unlock events, recalc attribution |
| `invoice.payment_failed` | Set past_due, start grace period |

### Idempotency
- Store `stripe_event_id` in `billing_events` table
- Skip if already processed

---

## Usage Tracking

### Architecture (Solid Stack)
```
Event API → Increment Counter (Solid Cache) → Check Limit/Status
                        ↓
         If past_due (post-grace): mark event locked: true
                        ↓
         Report to Stripe Meter (Solid Queue async job)
```

### Event Locking
- Add `locked` boolean to events table (default: false)
- Locked events excluded from:
  - Dashboard queries
  - Attribution calculations
  - Export downloads
- On payment success: `UPDATE events SET locked = false WHERE account_id = ? AND locked = true`
- Then trigger attribution recalculation for unlocked period

---

## Admin Dashboard

### Metrics
- MRR / ARR / Net Revenue / ARPA
- Total active / New / Churned / Churn rate
- Trial conversion rate
- Usage statistics

### Admin Actions
- [ ] Grant free_until to account
- [ ] Extend free_until date
- [ ] View account billing history
- [ ] Manually unlock events (edge cases)
- [ ] Grant trial extension

---

## Domain Model

### Account Billing Fields

| Field | Type | Purpose |
|-------|------|---------|
| `billing_status` | enum | Current state (free_forever, free_until, trialing, active, past_due, cancelled, expired) |
| `plan_id` | FK | Current plan |
| `stripe_customer_id` | string | Stripe customer |
| `stripe_subscription_id` | string | Stripe subscription |
| `free_until` | datetime | Admin-granted free access end date |
| `trial_ends_at` | datetime | Trial end |
| `subscription_started_at` | datetime | Paid subscription start |
| `current_period_start` | datetime | Billing period start |
| `current_period_end` | datetime | Billing period end |
| `payment_failed_at` | datetime | Last payment failure |
| `grace_period_ends_at` | datetime | When grace period ends (payment_failed_at + 3 days) |
| `billing_email` | string | Billing notifications |

### Events Table Addition

| Field | Type | Purpose |
|-------|------|---------|
| `locked` | boolean | True if stored during past_due (post-grace) |

### New Models

| Model | Purpose |
|-------|---------|
| `Plan` | Pricing tiers, limits, Stripe IDs |
| `BillingEvent` | Webhook event log (idempotency) |
| `OverageCharge` | Record of overage charges |

---

## File Structure

```
app/
├── controllers/
│   ├── billing_controller.rb
│   ├── webhooks/
│   │   └── stripe_controller.rb
│   └── admin/
│       └── billing_controller.rb
├── models/
│   ├── plan.rb
│   ├── billing_event.rb
│   ├── overage_charge.rb
│   └── concerns/account/billing.rb
├── services/billing/
│   ├── checkout_service.rb
│   ├── portal_service.rb
│   ├── usage_counter.rb
│   ├── unlock_events_service.rb
│   ├── metrics_service.rb
│   ├── webhook_handler.rb
│   └── handlers/
│       └── (all webhook handlers)
├── jobs/billing/
│   ├── report_usage_job.rb
│   ├── usage_alert_job.rb
│   ├── free_until_reminder_job.rb
│   ├── trial_reminder_job.rb
│   ├── expire_free_until_job.rb
│   └── recalculate_attribution_job.rb
├── mailers/
│   └── billing_mailer.rb
└── views/
    ├── billing/
    ├── billing_mailer/
    ├── admin/billing/
    └── shared/
        └── _billing_banner.html.erb
```

---

## Dependencies

### Gems
```ruby
gem "stripe"
gem "postmark-rails"
```

### Credentials
```yaml
stripe:
  secret_key: sk_live_xxx
  publishable_key: pk_live_xxx
  webhook_secret: whsec_xxx
  test_secret_key: sk_test_xxx
  meter_id: mtr_xxx

postmark:
  api_token: xxx
```

---

## Implementation Phases

### Phase 1: Foundation ✅ COMPLETE
- [x] Add gems (stripe, postmark-rails)
- [x] Create Plan model and migration
- [x] Seed plans (free, starter, growth, pro)
- [x] Add billing columns to Account migration
- [x] Add `locked` column to events migration
- [x] Create Account::Billing concern with all states
- [x] Create BillingEvent model (idempotency)
- [x] Create Billing constants module (no magic values)
- [x] Set up Stripe products/prices in test mode (sandbox)
- [ ] Configure Postmark credentials (deferred to Phase 7)

### Phase 2: Free Until & State Management ✅ COMPLETE
- [x] Implement free_until state logic (Account::Billing concern)
- [x] Implement can_ingest_events? for all states (Account::Billing concern)
- [x] Implement event locking for past_due (should_lock_events?)
- [x] Create Billing::UnlockEventsService
- [x] Add grant_free_until! / extend_free_until! methods
- [x] Create Billing::ExpireFreeUntilJob (daily check)
- [x] Comprehensive test coverage (60 tests)
- [ ] Admin UI for free_until management (deferred to Phase 8)

### Phase 3: Usage Tracking ✅ COMPLETE
- [x] Create Billing::UsageCounter (Solid Cache)
- [x] Integrate counter into event ingestion (IngestionService)
- [x] Add locked flag to events during post-grace past_due (ProcessingService)
- [x] Create Billing::ReportUsageService + thin job wrapper
- [x] Refactor ExpireFreeUntilJob to service pattern
- [x] Update CLAUDE.md with jobs-as-thin-wrappers guideline
- [ ] Set up Stripe Meter (deferred - requires Stripe dashboard config)
- [ ] Test usage tracking end-to-end (deferred to Phase 9)

### Phase 4: Dashboard Banners ✅ COMPLETE
- [x] Create shared billing banner partial
- [x] Implement past_due banner (red) with payment link
- [x] Implement free_until expiring banner (blue) with plans link
- [x] Implement usage limit/warning banners (amber) with upgrade links
- [x] Add banners to dashboard layout
- [x] Controller tests for all banner states (6 tests)

### Phase 5: Checkout & Portal
- [ ] Create Billing::CheckoutService
- [ ] Create Billing::PortalService
- [ ] Add BillingController
- [ ] Add routes (checkout, portal, success, cancel)
- [ ] Create pricing page UI
- [ ] Add "Manage Subscription" to account settings
- [ ] Test checkout flow with test cards

### Phase 6: Webhooks
- [ ] Create Webhooks::StripeController
- [ ] Implement signature verification
- [ ] Create Billing::WebhookHandler dispatcher
- [ ] Implement all webhook handlers
- [ ] On invoice.paid: unlock events + recalc attribution
- [ ] Configure webhook in Stripe Dashboard
- [ ] Test with Stripe CLI locally

### Phase 7: Emails
- [ ] Configure Postmark in production.rb
- [ ] Create BillingMailer
- [ ] Create all email templates
- [ ] Add email preview routes
- [ ] Implement all scheduled email jobs
- [ ] Test email delivery

### Phase 8: Admin Dashboard
- [ ] Create Admin::BaseController with auth
- [ ] Create Admin::BillingController
- [ ] Create Billing::MetricsService
- [ ] Build admin dashboard view
- [ ] Add MRR chart (Highcharts)
- [ ] Add free_until management UI
- [ ] Add account billing history view

### Phase 9: Testing & Polish
- [ ] Unit tests for all billing states
- [ ] Unit tests for event locking/unlocking
- [ ] Unit tests for all webhook handlers
- [ ] Integration tests for webhook flow
- [ ] System tests for checkout/upgrade flows
- [ ] System tests for free_until lifecycle
- [ ] System tests for past_due → payment → unlock flow
- [ ] Security review
- [ ] Update Terms of Service

---

## Testing Checklist (Metered Billing)

### Free Forever
- [ ] Events accepted up to 10K limit
- [ ] Events rejected after 10K
- [ ] Counter resets at period start
- [ ] Upgrade prompt shown at 80% and 100%

### Free Until
- [ ] Full access until date
- [ ] Reminder email 7 days before
- [ ] Reminder email 1 day before
- [ ] Transitions to expired on date
- [ ] Admin can extend date

### Trial
- [ ] Full plan access during trial
- [ ] Auto-converts with card on file
- [ ] Expires without card

### Active → Past Due
- [ ] 3 day grace period works normally
- [ ] Day 4+: events stored with locked: true
- [ ] Locked events hidden from dashboard
- [ ] Locked events excluded from attribution
- [ ] Banner shows on dashboard

### Past Due → Payment Success
- [ ] All locked events unlocked
- [ ] Attribution recalculated for unlocked period
- [ ] Banner removed
- [ ] Confirmation email sent

### Overage
- [ ] Overage calculated correctly per plan
- [ ] Reported to Stripe Meters
- [ ] Invoice includes overage charges

---

## Security Checklist

- [ ] Verify Stripe webhook signatures
- [ ] Store stripe_event_id for idempotency
- [ ] Never handle raw card numbers
- [ ] Store API keys in credentials
- [ ] Admin dashboard behind authentication
- [ ] Rate limit webhook endpoint
- [ ] Audit log for billing changes
- [ ] Audit log for free_until grants

---

## Sources

- [Stripe Best Practices for SaaS Billing](https://stripe.com/resources/more/best-practices-for-saas-billing)
- [Stripe Usage-Based Billing](https://docs.stripe.com/billing/subscriptions/usage-based)
- [Stripe Webhooks for Subscriptions](https://docs.stripe.com/billing/subscriptions/webhooks)
- [Postmark vs SendGrid Comparison](https://postmarkapp.com/compare/sendgrid-alternative)
