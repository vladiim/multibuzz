# Subscription & Billing Specification

**Status**: Planned
**Priority**: P0 (Required for launch)
**Last Updated**: 2025-11-29

---

## Overview

Defines mbuzz's subscription model, metered billing, and payment failure handling.

---

## Pricing Tiers

| Tier | Monthly Events | Base Price | Overage Rate (per 10K) |
|------|----------------|------------|------------------------|
| Free | ≤10K | $0 | N/A (hard cap) |
| Starter | ≤50K | $29 | $5.80 |
| Growth | ≤250K | $99 | $3.96 |
| Pro | ≤1M | $299 | $2.99 |
| Enterprise | 1M+ | Custom | Custom |

---

## Billing Model

### Prepaid Base Plan

1. User selects a plan (Starter, Growth, Pro)
2. Base plan fee charged **in advance** at start of billing cycle
3. This covers events up to the plan limit
4. Billing cycle: Monthly from signup date

### Metered Overage

When a user exceeds their plan's event limit:

1. **Immediate charge**: Card charged for one 10K block at plan's overage rate
2. **Block-based**: Always charged in full 10K blocks (no partial blocks)
3. **Real-time**: Charge happens when limit is crossed, not at end of month
4. **Cumulative**: Each additional 10K triggers another charge

**Example (Starter plan):**
- Day 1: User pays $29 (covers 50K events)
- Day 15: User hits 50K events → charge $5.80 (covers 50K-60K)
- Day 20: User hits 60K events → charge $5.80 (covers 60K-70K)
- Total for month: $29 + $5.80 + $5.80 = $40.60

### Free Tier

- Hard cap at 10K events per month
- When limit reached: **new events are not stored**
- No overage charges (no payment method on file)
- User must upgrade to continue tracking
- Counter resets at start of next billing cycle

---

## Payment Failure Handling

### When Overage Charge Fails

1. **Immediate**: Stop storing new events
2. **Notify**: Send email to account owner explaining payment failure
3. **Retry schedule**:
   - Attempt 1: Immediate (initial failure)
   - Attempt 2: 24 hours later
   - Attempt 3: 72 hours after attempt 2
   - Attempt 4: 7 days after attempt 3
4. **Total window**: 11 days from initial failure

### During Payment Failure

- New events are **not stored** (rejected at API level)
- Existing data remains accessible (read-only)
- Dashboard shows payment failure banner
- API returns `402 Payment Required` for event ingestion

### After Payment Succeeds

- Event ingestion resumes immediately
- Events lost during the outage are **not recoverable**
- No backfill or credit for lost events

### After All Retries Exhausted (11 days)

- Account status: `payment_failed`
- Event ingestion remains blocked
- User must manually update payment method
- Once updated: immediate charge attempt, resume if successful

### Base Plan Renewal Failure

If the monthly base plan charge fails:

1. **Grace period**: 3 days (events continue to be stored)
2. **After grace period**: Same as overage failure (stop storing)
3. **Retry schedule**: Same 4-attempt schedule
4. **Account suspension**: After all retries fail, account enters `suspended` state

---

## Event Counting

### What Counts as an Event

- Each API call to `/api/v1/events` counts as 1 event per event in payload
- Batch submissions: Each event in batch counted separately
- Failed events (validation errors): Do not count
- Duplicate events: Count (deduplication is customer responsibility)

### Counter Reset

- Resets at start of each billing cycle
- Billing cycle: Monthly anniversary of subscription start

### Real-time Tracking

- Event count updated in real-time
- Visible in dashboard: "X of Y events used this month"
- API endpoint: `GET /api/v1/usage` returns current count

---

## Notifications

### Usage Alerts

| Threshold | Notification |
|-----------|--------------|
| 80% of plan limit | Email: "Approaching your event limit" |
| 100% of plan limit | Email: "Event limit reached, overage charges apply" |
| Each overage block | Email: "Overage charge of $X.XX processed" |

### Payment Alerts

| Event | Notification |
|-------|--------------|
| Payment failed | Email: "Payment failed - action required" |
| Retry scheduled | Email: "We'll retry your payment in X hours" |
| Final retry failed | Email: "Urgent: Update payment method to continue" |
| Payment succeeded | Email: "Payment successful - service restored" |

---

## Plan Changes

### Upgrades

- Immediate effect
- Prorated credit for unused portion of current plan
- New plan limit applies immediately
- Billed prorated amount for remainder of cycle

### Downgrades

- Takes effect at next billing cycle
- Current plan remains active until cycle ends
- If current usage exceeds new plan limit: overage charges apply on new plan

### Cancellation

- Takes effect at end of billing cycle
- No prorated refunds for partial months
- Data retained per data retention policy (see `data_retention_spec.md`)
- Account can be reactivated within 90 days

---

## Key Objects

| Object | Purpose |
|--------|---------|
| `Subscription` | Tracks plan, status, billing cycle |
| `UsageCounter` | Real-time event count per account per cycle |
| `PaymentAttempt` | Log of all charge attempts and results |
| `OverageCharge` | Record of each overage block charged |
| `Billing::ChargeService` | Handles Stripe charges |
| `Billing::RetryJob` | Scheduled job for payment retries |
| `Billing::UsageAlertJob` | Sends threshold notifications |

---

## Database Changes

| Table | Change |
|-------|--------|
| `subscriptions` | `plan`, `status`, `current_period_start`, `current_period_end` |
| `subscriptions` | `event_count`, `overage_blocks_charged` |
| `payment_attempts` | New table: `subscription_id`, `amount`, `status`, `attempted_at`, `failure_reason` |
| `overage_charges` | New table: `subscription_id`, `amount`, `block_number`, `charged_at` |

---

## Stripe Integration

- Use Stripe for all payment processing
- Store `stripe_customer_id` on Account
- Store `stripe_subscription_id` on Subscription
- Use Stripe's metered billing for overage (usage records)
- Webhook handlers for payment events

---

## Edge Cases

### Rapid Overage

If user burns through multiple 10K blocks quickly:
- Each block charged separately as limit is crossed
- No batching or delay
- Could result in multiple charges in short period

### Disputed Charges

- Follow Stripe's dispute process
- Service continues during dispute
- If dispute won by customer: credit applied, no service interruption

### Currency

- All prices in USD
- Stripe handles currency conversion for international cards

---

## Terms of Service Alignment

This spec is the source of truth for billing terms. The Terms of Service (`app/views/pages/terms.html.erb`) must reflect:

1. Prepaid base plan model
2. Real-time overage charging in 10K blocks
3. Payment failure = service interruption
4. Lost events during outage are not recoverable
5. Free tier hard cap with no overage option
