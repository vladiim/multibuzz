# Spec: Recurring Revenue Attribution

## Overview

Enable recurring payments to link back to original customer acquisition using the existing `user_id` (Identity) system. Add two boolean flags to conversions:

- `is_acquisition: true` - marks THIS as the acquisition conversion for the user
- `inherit_acquisition: true` - inherit attribution from user's acquisition conversion

**Key Insight**: No new models. No SDK changes. Uses existing Identity system. Just two new fields.

---

## Problem Statement

Current attribution stops at first conversion. For SaaS/subscription businesses:

- **First payment** gets attributed to channels
- **Renewals/upgrades** are orphaned - no attribution
- **No way to calculate**: LTV by channel, CAC payback period, retention by acquisition source

## Solution

Every subscription payment inherits attribution from the original acquisition:

```ruby
# 1. User signs up - mark as acquisition conversion
mbuzz.identify(user_id: "user_123", visitor_id: vid)
mbuzz.conversion(
  user_id: "user_123",
  conversion_type: "signup",
  is_acquisition: true  # <-- This is THE acquisition moment
)

# 2. User pays (any time later) - inherit acquisition attribution
mbuzz.conversion(
  user_id: "user_123",
  conversion_type: "payment",
  revenue: 49.00,
  inherit_acquisition: true  # <-- Auto-finds acquisition, inherits attribution
)
```

When `inherit_acquisition: true`:
1. Look up user's acquisition conversion (where `is_acquisition: true`)
2. Copy attribution credits from that conversion
3. Recalculate `revenue_credit` based on THIS conversion's revenue

---

## API Changes

### POST /api/v1/conversions - New Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `user_id` | string | null | User ID - links to Identity (required for acquisition features) |
| `is_acquisition` | boolean | false | Mark this as the acquisition conversion for this user |
| `inherit_acquisition` | boolean | false | Inherit attribution from user's acquisition conversion |

### Example: Full SaaS Flow

```ruby
# Step 1: Identify user on signup
mbuzz.identify(
  user_id: "user_123",
  visitor_id: visitor_id,
  traits: { email: "jane@example.com" }
)

# Step 2: Track signup as acquisition
mbuzz.conversion(
  user_id: "user_123",
  conversion_type: "signup",
  is_acquisition: true
)
# => Attribution calculated normally from visitor's sessions

# Step 3: First payment (linked to acquisition)
mbuzz.conversion(
  user_id: "user_123",
  conversion_type: "first_payment",
  revenue: 49.00,
  inherit_acquisition: true
)
# => Attribution inherited from signup

# Step 4: Renewal payment (same thing)
mbuzz.conversion(
  user_id: "user_123",
  conversion_type: "renewal",
  revenue: 49.00,
  inherit_acquisition: true
)
# => Attribution inherited from signup
```

---

## Data Model

### Migration: Add fields to conversions

```ruby
class AddAcquisitionFieldsToConversions < ActiveRecord::Migration[8.0]
  def change
    add_column :conversions, :is_acquisition, :boolean, default: false, null: false
    add_reference :conversions, :identity, foreign_key: true, null: true

    add_index :conversions, [:account_id, :identity_id, :is_acquisition],
      name: "index_conversions_on_acquisition_lookup"
  end
end
```

### Schema Changes

```ruby
conversions
  # ... existing fields ...
  t.boolean :is_acquisition, default: false, null: false  # NEW
  t.bigint :identity_id, null: true                        # NEW - links to user
```

---

## Service Changes

### 1. `Conversions::TrackingService`

Accept `user_id`, `is_acquisition`, `inherit_acquisition` params:

```ruby
def initialize(account, params, is_test: false)
  # ... existing ...
  @user_id = params[:user_id]
  @is_acquisition = params[:is_acquisition] || false
  @inherit_acquisition = params[:inherit_acquisition] || false
end

def conversion
  @conversion ||= Conversion.create!(
    # ... existing fields ...
    identity_id: resolved_identity&.id,
    is_acquisition: @is_acquisition
  ).tap { |c| c.inherit_acquisition = @inherit_acquisition }
end

def resolved_identity
  return nil unless @user_id.present?
  @resolved_identity ||= account.identities.find_by(external_id: @user_id)
end
```

### 2. `Conversions::AttributionCalculationService`

Inherit attribution when `inherit_acquisition` is true:

```ruby
def run
  if should_inherit_acquisition?
    inherit_acquisition_attribution
  else
    calculate_fresh_attribution
  end
  success_result(credits_by_model: credits_by_model)
end

private

def should_inherit_acquisition?
  conversion.inherit_acquisition? && acquisition_conversion.present?
end

def acquisition_conversion
  return nil unless conversion.identity_id.present?
  @acquisition_conversion ||= conversion.account.conversions
    .where(identity_id: conversion.identity_id, is_acquisition: true)
    .order(converted_at: :desc)
    .first
end

def inherit_acquisition_attribution
  @credits_by_model = {}
  active_models.each do |model|
    @credits_by_model[model.name] = inherit_credits_for_model(model)
  end
end

def inherit_credits_for_model(model)
  acquisition_conversion.attribution_credits
    .where(attribution_model: model)
    .map do |source_credit|
      AttributionCredit.create!(
        account: conversion.account,
        conversion: conversion,
        attribution_model: model,
        session_id: source_credit.session_id,
        channel: source_credit.channel,
        credit: source_credit.credit,
        revenue_credit: source_credit.credit * (conversion.revenue || 0),
        utm_source: source_credit.utm_source,
        utm_medium: source_credit.utm_medium,
        utm_campaign: source_credit.utm_campaign,
        is_test: conversion.is_test
      )
    end
end
```

### 3. Conversion Model

Add transient attribute for `inherit_acquisition`:

```ruby
# app/models/conversion.rb
attr_accessor :inherit_acquisition

def inherit_acquisition?
  @inherit_acquisition == true || @inherit_acquisition == "true"
end
```

---

## Validation Rules

1. `is_acquisition: true` requires `user_id` to be present
2. `inherit_acquisition: true` requires `user_id` to be present
3. If multiple `is_acquisition: true` exist for user, use most recent
4. `inherit_acquisition` without acquisition conversion → log warning, calculate fresh attribution

---

## Identity Link Flow

```
User signs up → identify(user_id: "123", visitor_id: "abc")
                     ↓
                 Identity created (external_id: "123")
                     ↓
                 Visitor linked (visitor.identity_id = identity.id)
                     ↓
conversion(user_id: "123", is_acquisition: true)
                     ↓
                 Conversion linked (conversion.identity_id = identity.id)
                     ↓
conversion(user_id: "123", inherit_acquisition: true)
                     ↓
                 Finds acquisition conversion via identity_id
                     ↓
                 Copies attribution credits with new revenue
```

---

## Reporting Queries

### LTV by Acquisition Channel

```sql
SELECT
  ac.channel,
  SUM(ac.revenue_credit) as total_ltv,
  COUNT(DISTINCT c.identity_id) as customers
FROM attribution_credits ac
JOIN conversions c ON c.id = ac.conversion_id
WHERE ac.account_id = ?
  AND c.identity_id IS NOT NULL
GROUP BY ac.channel
ORDER BY total_ltv DESC;
```

### Customer LTV

```sql
SELECT
  c.identity_id,
  SUM(c.revenue) as total_revenue,
  COUNT(*) as payment_count
FROM conversions c
WHERE c.account_id = ?
  AND c.identity_id = ?
GROUP BY c.identity_id;
```

---

## Dogfood Plan

For mbuzz.co itself:

| Event | conversion_type | is_acquisition | inherit_acquisition |
|-------|-----------------|----------------|---------------------|
| Sign up | signup | true | false |
| First test event | activation | false | false |
| First prod event | production_active | false | false |
| First payment | first_payment | false | true |
| Renewal | renewal | false | true |

---

## SDK Impact

**None!** Existing SDK passes through params:

```ruby
mbuzz.conversion(
  user_id: "user_123",
  conversion_type: "renewal",
  revenue: 49.00,
  is_acquisition: true,
  inherit_acquisition: true
)
```

The 4-call model remains: `session`, `event`, `identify`, `conversion`.

---

## Implementation Checklist

### Phase 1: Database & Models ✅

- [x] Create migration `add_acquisition_fields_to_conversions`
  - [x] Add `is_acquisition` boolean column (default: false, null: false)
  - [x] Add `identity_id` reference column (foreign key to identities, nullable)
  - [x] Add composite index `[:account_id, :identity_id, :is_acquisition]`
- [x] Run migration locally
- [x] Update `app/models/conversion.rb`
  - [x] Add `attr_accessor :inherit_acquisition`
  - [x] Add `inherit_acquisition?` method (uses `ActiveModel::Type::Boolean.new.cast`)
- [x] Update `app/models/concerns/conversion/relationships.rb`
  - [x] Add `belongs_to :identity, optional: true`
- [x] Update `app/models/concerns/conversion/validations.rb`
  - [x] Add validation: `is_acquisition` requires `identity_id`
- [x] Update `app/models/concerns/identity/relationships.rb`
  - [x] Add `has_many :conversions, dependent: :nullify`
- [x] Write model tests `test/models/conversion_test.rb`
  - [x] Test `inherit_acquisition?` returns true/false correctly
  - [x] Test identity relationship
  - [x] Test validation for is_acquisition requiring identity

### Phase 2: Services ✅

- [x] Update `app/services/conversions/tracking_service.rb`
  - [x] Accept `user_id` param in initialize
  - [x] Accept `is_acquisition` param in initialize
  - [x] Accept `inherit_acquisition` param in initialize
  - [x] Add `resolved_identity` method to find Identity by external_id
  - [x] Set `identity_id` on conversion creation
  - [x] Set `is_acquisition` on conversion creation
  - [x] Set `inherit_acquisition` transient attribute on conversion
- [x] Write tests `test/services/conversions/tracking_service_test.rb`
  - [x] Test conversion created with identity_id when user_id provided
  - [x] Test conversion created with is_acquisition flag
  - [x] Test inherit_acquisition is set on conversion object
  - [x] Test user_id without existing identity returns nil identity_id
  - [x] Test user_id with existing identity links correctly

- [x] Update `app/services/conversions/attribution_calculation_service.rb`
  - [x] Add `should_inherit_acquisition?` method
  - [x] Add `acquisition_conversion` method to find user's acquisition conversion
  - [x] Add `inherit_acquisition_attribution` method
  - [x] Add `inherit_credits_for_model` method
  - [x] Modify `run` to check for inheritance before fresh calculation
- [x] Write tests `test/services/conversions/attribution_calculation_service_test.rb`
  - [x] Test fresh attribution when no inherit flag
  - [x] Test fresh attribution when inherit flag but no acquisition conversion
  - [x] Test inherited attribution copies credits correctly
  - [x] Test inherited attribution recalculates revenue_credit
  - [x] Test inherited attribution preserves channel/UTM data
  - [x] Test inherited attribution works with multiple attribution models

### Phase 3: API ✅

- [x] Update `app/controllers/api/v1/conversions_controller.rb`
  - [x] Permit `user_id` param
  - [x] Permit `is_acquisition` param
  - [x] Permit `inherit_acquisition` param

### Phase 4: Documentation ✅

- [x] Update API documentation for `/api/v1/conversions` (`lib/docs/sdk/api_contract.md`)
  - [x] Document `user_id` field
  - [x] Document `is_acquisition` field
  - [x] Document `inherit_acquisition` field
  - [x] Add example for SaaS recurring revenue flow

### Phase 5: Dogfooding

- [ ] Create "Multibuzz Internal" account in seeds or manually
- [ ] Generate API keys for internal account
- [ ] Hook account creation to track `signup` conversion with `is_acquisition: true`
- [ ] Hook `checkout.session.completed` webhook to track `first_payment` with `inherit_acquisition: true`
- [ ] Hook `invoice.paid` webhook to track `renewal` with `inherit_acquisition: true`
- [ ] Verify attribution flows correctly in dashboard

### Phase 6: QA & Deploy

- [x] Run full test suite (1729 tests, 0 failures)
- [ ] Test manually in development
- [ ] Deploy migration to production
- [ ] Deploy code to production
- [ ] Verify in production with test account
- [ ] Enable dogfooding in production

---

## Files to Create/Modify

### New Files
- `db/migrate/YYYYMMDDHHMMSS_add_acquisition_fields_to_conversions.rb`

### Modified Files
- `app/models/conversion.rb`
- `app/models/concerns/conversion/relationships.rb`
- `app/models/concerns/conversion/validations.rb`
- `app/models/concerns/identity/relationships.rb`
- `app/services/conversions/tracking_service.rb`
- `app/services/conversions/attribution_calculation_service.rb`
- `app/controllers/api/v1/conversions_controller.rb`
- `test/fixtures/conversions.yml`
- `test/models/conversion_test.rb`
- `test/services/conversions/tracking_service_test.rb`
- `test/services/conversions/attribution_calculation_service_test.rb`
- `test/controllers/api/v1/conversions_controller_test.rb`

---

## Sources

- [Spectacle - Stripe Marketing Attribution](https://www.spectaclehq.com/blog/stripe-marketing-attribution-integration)
- [Stripe CAC Guide](https://stripe.com/resources/more/cac-in-saas)
- [Neil Patel - Cohort Analysis & MTA](https://neilpatel.com/blog/cohort-and-multi-touch-attribution/)
- [HockeyStack - B2B Multi-Touch Attribution](https://www.hockeystack.com/blog-posts/b2b-multi-touch-attribution)
