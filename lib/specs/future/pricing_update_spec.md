# Pricing Update Specification

## Overview

Update Multibuzz pricing tiers to be right-sized for attribution use case (not general analytics), with sustainable margins while maintaining competitive positioning.

---

## New Pricing Structure

| Tier | Monthly | Events Included | Overage Block | Block Price | Effective $/1K |
|------|---------|-----------------|---------------|-------------|----------------|
| **Free** | $0 | 50K | Hard cap | — | — |
| **Starter** | $29 | 1M | 250K | $5 | $0.029 (included), $20/1M (overage) |
| **Growth** | $99 | 5M | 1M | $15 | $0.020 (included), $15/1M (overage) |
| **Pro** | $299 | 25M | 5M | $50 | $0.012 (included), $10/1M (overage) |
| **Enterprise** | Contact us | Custom | Custom | Custom | Custom |

---

## Previous vs New Pricing

| Aspect | Previous | New |
|--------|----------|-----|
| Free events | 10K | 50K |
| Starter events | 50K | 1M |
| Growth events | 250K | 5M |
| Pro events | 1M | 25M |
| Overage unit | 10K blocks | 250K/1M/5M blocks (tier-scaled) |
| Starter overage | $5.80/10K | $5/250K ($20/1M) |
| Growth overage | $3.96/10K | $15/1M |
| Pro overage | $2.99/10K | $50/5M ($10/1M) |

---

## Rationale

### Why Increase Event Limits?

1. **Attribution ≠ Analytics**: Customers track visits, key events, and conversions — not every pageview. Lower volume per customer than Mixpanel/PostHog users.

2. **Generous positioning**: "1 million events for $29" is a strong headline that differentiates from competitors.

3. **Margin-safe**: At estimated $3/1M cost:
   - Starter (1M): 90% margin
   - Growth (5M): 85% margin
   - Pro (25M): 75% margin

4. **Room to grow**: Can increase limits later as a retention/expansion play. Cannot decrease without angering customers.

### Why Change Overage Mechanics?

Previous: 10K blocks at every tier (too granular, causes bill anxiety)

New: Tier-scaled blocks that encourage upgrading:
- Starter: 250K @ $5 → $20/1M overage
- Growth: 1M @ $15 → $15/1M overage
- Pro: 5M @ $50 → $10/1M overage

Built-in volume discount makes upgrading tier always better than buying many overage blocks.

---

## Constants Update

```ruby
# app/constants/billing.rb

# Event limits
FREE_EVENT_LIMIT = 50_000           # was 10_000
STARTER_EVENT_LIMIT = 1_000_000     # was 50_000
GROWTH_EVENT_LIMIT = 5_000_000      # was 250_000
PRO_EVENT_LIMIT = 25_000_000        # was 1_000_000

# Monthly prices (unchanged)
FREE_MONTHLY_PRICE_CENTS = 0
STARTER_MONTHLY_PRICE_CENTS = 2900
GROWTH_MONTHLY_PRICE_CENTS = 9900
PRO_MONTHLY_PRICE_CENTS = 29900

# Overage block sizes (NEW)
STARTER_OVERAGE_BLOCK_SIZE = 250_000
GROWTH_OVERAGE_BLOCK_SIZE = 1_000_000
PRO_OVERAGE_BLOCK_SIZE = 5_000_000

# Overage prices per block (NEW structure)
STARTER_OVERAGE_CENTS = 500         # $5 per 250K block
GROWTH_OVERAGE_CENTS = 1500         # $15 per 1M block
PRO_OVERAGE_CENTS = 5000            # $50 per 5M block
```

---

## Stripe Updates Required

### New Products/Prices Needed

Since event limits and overage pricing are changing significantly, create new Stripe prices:

1. **Metered prices** for each tier (for overage billing)
   - Starter: $5 per 250K events over 1M
   - Growth: $15 per 1M events over 5M
   - Pro: $50 per 5M events over 25M

2. **Update Stripe Meters** to use new block sizes

### Stripe Configuration Steps (Test Mode)

1. **Go to Stripe Dashboard** > Products

2. **Create/Update Metered Prices for each plan:**

   **Starter Plan:**
   - Create new metered price: $5 per 250K events
   - Meter event name: `starter_overage_events`
   - Billing scheme: Per unit
   - Unit amount: $5.00 (500 cents)
   - Aggregate usage: Sum

   **Growth Plan:**
   - Create new metered price: $15 per 1M events
   - Meter event name: `growth_overage_events`
   - Billing scheme: Per unit
   - Unit amount: $15.00 (1500 cents)
   - Aggregate usage: Sum

   **Pro Plan:**
   - Create new metered price: $50 per 5M events
   - Meter event name: `pro_overage_events`
   - Billing scheme: Per unit
   - Unit amount: $50.00 (5000 cents)
   - Aggregate usage: Sum

3. **Update Rails credentials:**
   ```bash
   EDITOR="code --wait" rails credentials:edit
   ```

   Add/update:
   ```yaml
   stripe:
     prices:
       starter: price_xxxxx  # Your Stripe price ID
       growth: price_xxxxx
       pro: price_xxxxx
     meters:
       starter: mtr_xxxxx
       growth: mtr_xxxxx
       pro: mtr_xxxxx
   ```

4. **Update db/seeds.rb** if Stripe IDs are hardcoded there (they should reference credentials)

5. **Test in Stripe Test Mode:**
   - Create a test subscription
   - Report usage via API
   - Verify metered billing works correctly

### Production Rollout

1. Repeat Stripe configuration steps in **Live Mode**
2. Update production credentials via `rails credentials:edit --environment production`
3. Deploy code changes
4. Migrate existing subscriptions to new prices at next billing cycle

---

## Files to Update

### Primary (Required)

| File | Changes |
|------|---------|
| `app/constants/billing.rb` | Update all event limits, add block sizes, update overage prices |
| `app/views/pages/home/_pricing.html.erb` | Update displayed limits and effective pricing |
| `test/fixtures/plans.yml` | Update test fixture values |
| `db/seeds.rb` | Verify references constants (should auto-update) |
| Rails credentials | Add new Stripe price IDs |

### Secondary (Auto-Reference Constants)

These files reference `Billing::` constants and should work automatically:

| File | Notes |
|------|-------|
| `app/models/plan.rb` | Uses `plan.events_included` from DB |
| `app/models/concerns/account/billing.rb` | References `Billing::FREE_EVENT_LIMIT` |
| `app/services/billing/usage_counter.rb` | Uses plan limits |
| `app/services/billing/report_usage_service.rb` | Calculates overage from plan |

### Model Changes

The `Plan` model needs to support variable block sizes:

```ruby
# Add to plans table
add_column :plans, :overage_block_size, :integer, default: 10_000
```

Or handle in constants:
```ruby
OVERAGE_BLOCK_SIZES = {
  free: nil,
  starter: 250_000,
  growth: 1_000_000,
  pro: 5_000_000
}.freeze
```

### View Updates

`app/views/pages/home/_pricing.html.erb` needs:
- Update event limits (50K, 1M, 5M, 25M)
- Update effective per-1K pricing
- Update overage description (block-based, not 10K increments)
- Add Enterprise tier placeholder

---

## Migration Strategy

### For Existing Customers

1. **Grandfather existing limits** for current billing cycle
2. **Apply new limits** at next renewal
3. **Communicate change** as upgrade: "You now get 20x more events at the same price!"

### For Stripe

1. Create new prices (don't delete old ones)
2. Migrate subscriptions to new prices at renewal
3. Keep old prices for historical billing

---

## Testing Checklist

- [ ] Constants updated in `billing.rb`
- [ ] Seeds create plans with new limits
- [ ] Fixtures updated for tests
- [ ] Usage counter respects new limits
- [ ] Overage calculation uses new block sizes
- [ ] Pricing page displays correctly
- [ ] Billing dashboard shows correct limits
- [ ] Usage alerts trigger at correct percentages
- [ ] Stripe metered billing reports correct blocks

---

## Rollout Plan

1. **Create Stripe prices** (test mode first)
2. **Update constants and views**
3. **Run migrations** (if adding block_size column)
4. **Update seeds and fixtures**
5. **Deploy to staging** and verify
6. **Create production Stripe prices**
7. **Deploy to production**
8. **Email existing customers** about the upgrade
