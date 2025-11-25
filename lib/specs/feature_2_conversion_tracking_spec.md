# Feature 2: Conversion Tracking & Automatic Attribution

**Status**: 🚧 Implementation Required
**Priority**: Critical
**Created**: 2025-11-25
**Last Updated**: 2025-11-25

---

## Overview

This feature enables automatic attribution calculation when conversions are created. When a user converts (signup, purchase, etc.), the system automatically:

1. Creates a Conversion record
2. Builds the visitor's journey (all sessions in lookback window)
3. Runs attribution algorithms for all active models
4. Stores AttributionCredit records
5. Returns attribution results to the caller

---

## Current State

### ✅ What Exists (Working)

| Component | Location | Status |
|-----------|----------|--------|
| `Conversion` model | `app/models/conversion.rb` | ✅ Complete |
| `AttributionCredit` model | `app/models/attribution_credit.rb` | ✅ Complete |
| `AttributionModel` model | `app/models/attribution_model.rb` | ✅ Complete |
| `Attribution::Calculator` | `app/services/attribution/calculator.rb` | ✅ Complete |
| `Attribution::JourneyBuilder` | `app/services/attribution/journey_builder.rb` | ✅ Complete |
| `Attribution::Algorithms::FirstTouch` | `app/services/attribution/algorithms/first_touch.rb` | ✅ Complete |
| `Attribution::Algorithms::LastTouch` | `app/services/attribution/algorithms/last_touch.rb` | ✅ Complete |
| `Attribution::Algorithms::Linear` | `app/services/attribution/algorithms/linear.rb` | ✅ Complete |

### ❌ What's Missing (To Implement)

| Component | Location | Purpose |
|-----------|----------|---------|
| `Conversions::TrackingService` | `app/services/conversions/tracking_service.rb` | Creates conversion, triggers attribution |
| `Conversions::AttributionCalculationService` | `app/services/conversions/attribution_calculation_service.rb` | Runs all active models, stores credits |
| `Conversion::Callbacks` | `app/models/concerns/conversion/callbacks.rb` | `after_create` hook to trigger attribution |
| `Conversions::AttributionCalculationJob` | `app/jobs/conversions/attribution_calculation_job.rb` | Async attribution processing |
| `Api::V1::ConversionsController` | `app/controllers/api/v1/conversions_controller.rb` | API endpoint |

---

## API Contract

### POST /api/v1/conversions

Creates a conversion and triggers attribution calculation.

**Request**:
```json
{
  "conversion": {
    "event_id": "evt_abc123",
    "conversion_type": "signup",
    "revenue": 99.99
  }
}
```

**Required Fields**:
- `event_id` (string) - Prefixed ID of the event that represents the conversion
- `conversion_type` (string) - User-defined type (e.g., "signup", "purchase", "trial_start")

**Optional Fields**:
- `revenue` (decimal) - Revenue amount for revenue attribution

**Response (201 Created)**:
```json
{
  "conversion": {
    "id": "conv_xyz789",
    "conversion_type": "signup",
    "revenue": "99.99",
    "converted_at": "2025-11-25T04:00:00Z",
    "visitor_id": "vis_abc123",
    "journey_sessions": 4
  },
  "attribution": {
    "status": "calculated",
    "models": {
      "first_touch": [
        {
          "channel": "organic_search",
          "credit": 1.0,
          "revenue_credit": "99.99",
          "utm_source": "google",
          "utm_medium": null,
          "utm_campaign": null
        }
      ],
      "linear": [
        {
          "channel": "organic_search",
          "credit": 0.25,
          "revenue_credit": "24.99",
          "utm_source": "google",
          "utm_medium": null,
          "utm_campaign": null
        },
        {
          "channel": "paid_social",
          "credit": 0.25,
          "revenue_credit": "24.99",
          "utm_source": "facebook",
          "utm_medium": "paid_social",
          "utm_campaign": "retargeting"
        },
        {
          "channel": "email",
          "credit": 0.25,
          "revenue_credit": "24.99",
          "utm_source": "mailchimp",
          "utm_medium": "email",
          "utm_campaign": "nurture"
        },
        {
          "channel": "direct",
          "credit": 0.25,
          "revenue_credit": "24.99",
          "utm_source": null,
          "utm_medium": null,
          "utm_campaign": null
        }
      ],
      "last_touch": [
        {
          "channel": "direct",
          "credit": 1.0,
          "revenue_credit": "99.99",
          "utm_source": null,
          "utm_medium": null,
          "utm_campaign": null
        }
      ]
    }
  }
}
```

**Error Response (422 Unprocessable Entity)**:
```json
{
  "success": false,
  "errors": ["Event not found", "conversion_type is required"]
}
```

**Error Response (401 Unauthorized)**:
```json
{
  "error": "Invalid API key"
}
```

---

## Service Architecture

### Flow Diagram

```
API Request
    │
    ▼
┌─────────────────────────────────────┐
│  Api::V1::ConversionsController     │
│  - Authenticate API key             │
│  - Parse params                     │
│  - Call TrackingService             │
└───────────────┬─────────────────────┘
                │
                ▼
┌─────────────────────────────────────┐
│  Conversions::TrackingService       │
│  - Find Event by prefix_id          │
│  - Validate conversion_type         │
│  - Create Conversion record         │
│  - Trigger AttributionCalculation   │
│  - Return result                    │
└───────────────┬─────────────────────┘
                │
                ▼
┌─────────────────────────────────────┐
│  Conversions::AttributionCalc...    │
│  - Get active AttributionModels     │
│  - For each model:                  │
│    - Call Attribution::Calculator   │
│    - Store AttributionCredits       │
│  - Return all credits               │
└───────────────┬─────────────────────┘
                │
                ▼
┌─────────────────────────────────────┐
│  Attribution::Calculator            │
│  - Build journey (JourneyBuilder)   │
│  - Run algorithm (FirstTouch, etc.) │
│  - Enrich with session data         │
│  - Add revenue credits              │
│  - Return credit array              │
└─────────────────────────────────────┘
```

### Service Specifications

#### Conversions::TrackingService

**Purpose**: Orchestrates conversion creation and attribution calculation.

**Input**:
```ruby
Conversions::TrackingService.new(account, conversion_params).call
```

**Parameters**:
- `account` - Current authenticated account
- `conversion_params` - Hash with `event_id`, `conversion_type`, `revenue`

**Output**:
```ruby
# Success
{
  success: true,
  conversion: Conversion,
  attribution_credits: {
    "first_touch" => [...],
    "linear" => [...],
    "last_touch" => [...]
  }
}

# Failure
{
  success: false,
  errors: ["Event not found"]
}
```

**Responsibilities**:
1. Find Event by `prefix_id` (not raw ID)
2. Validate event belongs to account
3. Validate `conversion_type` is present
4. Extract visitor and session from event
5. Create Conversion record
6. Call `AttributionCalculationService`
7. Return combined result

---

#### Conversions::AttributionCalculationService

**Purpose**: Runs attribution calculation for all active models and stores credits.

**Input**:
```ruby
Conversions::AttributionCalculationService.new(conversion).call
```

**Output**:
```ruby
{
  success: true,
  credits_by_model: {
    "first_touch" => [{ channel: "organic_search", credit: 1.0, ... }],
    "linear" => [...],
    "last_touch" => [...]
  }
}
```

**Responsibilities**:
1. Get all active `AttributionModel` records for account
2. For each model:
   - Call `Attribution::Calculator`
   - Create `AttributionCredit` records
3. Return all credits grouped by model

---

#### Conversion::Callbacks

**Purpose**: Trigger attribution calculation automatically on conversion creation.

**Implementation**:
```ruby
module Conversion::Callbacks
  extend ActiveSupport::Concern

  included do
    after_create_commit :queue_attribution_calculation
  end

  private

  def queue_attribution_calculation
    Conversions::AttributionCalculationJob.perform_later(id)
  end
end
```

**Note**: Use `after_create_commit` to ensure transaction is committed before job runs.

---

#### Conversions::AttributionCalculationJob

**Purpose**: Async processing of attribution calculation.

**Implementation**:
```ruby
module Conversions
  class AttributionCalculationJob < ApplicationJob
    queue_as :default

    def perform(conversion_id)
      conversion = Conversion.find(conversion_id)
      Conversions::AttributionCalculationService.new(conversion).call
    end
  end
end
```

---

## Database Considerations

### Conversion Table

Current schema (no changes needed):
```ruby
create_table "conversions" do |t|
  t.bigint "account_id", null: false
  t.bigint "visitor_id", null: false
  t.bigint "session_id", null: false
  t.bigint "event_id", null: false
  t.string "conversion_type", null: false
  t.decimal "revenue", precision: 10, scale: 2
  t.datetime "converted_at", null: false
  t.bigint "journey_session_ids", default: [], array: true
  t.timestamps
end
```

### AttributionCredit Table

Current schema (no changes needed):
```ruby
create_table "attribution_credits" do |t|
  t.bigint "account_id", null: false
  t.bigint "conversion_id", null: false
  t.bigint "attribution_model_id", null: false
  t.bigint "session_id", null: false
  t.string "channel", null: false
  t.decimal "credit", precision: 5, scale: 4, null: false
  t.decimal "revenue_credit", precision: 10, scale: 2
  t.string "utm_source"
  t.string "utm_medium"
  t.string "utm_campaign"
  t.timestamps
end
```

---

## Test Requirements

### Unit Tests

#### Conversions::TrackingService

```ruby
# test/services/conversions/tracking_service_test.rb
class Conversions::TrackingServiceTest < ActiveSupport::TestCase
  test "creates conversion from valid event" do
    # ...
  end

  test "returns error for invalid event_id" do
    # ...
  end

  test "returns error for event from different account" do
    # ...
  end

  test "returns error for missing conversion_type" do
    # ...
  end

  test "calculates attribution for all active models" do
    # ...
  end

  test "stores revenue when provided" do
    # ...
  end

  test "stores journey_session_ids" do
    # ...
  end
end
```

#### Conversions::AttributionCalculationService

```ruby
# test/services/conversions/attribution_calculation_service_test.rb
class Conversions::AttributionCalculationServiceTest < ActiveSupport::TestCase
  test "calculates credits for all active models" do
    # ...
  end

  test "stores attribution credits in database" do
    # ...
  end

  test "calculates revenue credits when conversion has revenue" do
    # ...
  end

  test "handles visitor with no sessions gracefully" do
    # ...
  end

  test "respects lookback_days setting" do
    # ...
  end
end
```

#### Api::V1::ConversionsController

```ruby
# test/controllers/api/v1/conversions_controller_test.rb
class Api::V1::ConversionsControllerTest < ActionDispatch::IntegrationTest
  test "creates conversion with valid params" do
    # ...
  end

  test "returns 401 without API key" do
    # ...
  end

  test "returns 422 with invalid params" do
    # ...
  end

  test "returns attribution credits in response" do
    # ...
  end

  test "prevents cross-account event access" do
    # ...
  end
end
```

### Integration Tests

```ruby
# test/integration/conversion_attribution_flow_test.rb
class ConversionAttributionFlowTest < ActionDispatch::IntegrationTest
  test "full flow: track events -> create conversion -> verify attribution" do
    # 1. Track multiple events with different channels
    # 2. Create conversion via API
    # 3. Verify Conversion record created
    # 4. Verify AttributionCredit records created for each model
    # 5. Verify credits sum to 1.0 for each model
    # 6. Verify revenue credits calculated correctly
  end
end
```

---

## Implementation Checklist

### Phase 1: Services (Day 1)

- [ ] Create `app/services/conversions/tracking_service.rb`
- [ ] Create `app/services/conversions/attribution_calculation_service.rb`
- [ ] Create `app/models/concerns/conversion/callbacks.rb`
- [ ] Update `app/models/conversion.rb` to include callbacks
- [ ] Create `app/jobs/conversions/attribution_calculation_job.rb`
- [ ] Write unit tests for all services

### Phase 2: API Endpoint (Day 1)

- [ ] Create `app/controllers/api/v1/conversions_controller.rb`
- [ ] Add route in `config/routes.rb`
- [ ] Write controller tests
- [ ] Test with curl/Postman

### Phase 3: Integration & Docs (Day 2)

- [ ] Write integration tests
- [ ] Run full test suite
- [ ] Update OpenAPI spec (`docs/api/openapi.yml`)
- [ ] Update implementation roadmap
- [ ] Test in production

---

## Design Decisions

### 1. Synchronous vs Asynchronous Attribution

**Decision**: Hybrid approach

- **Synchronous**: API returns conversion immediately with attribution results
- **Asynchronous**: `after_create_commit` also queues job for redundancy

**Rationale**:
- Immediate feedback is valuable for API consumers
- Background job ensures attribution runs even if inline calculation fails
- Job is idempotent (can re-run safely)

### 2. Which Attribution Models Run

**Decision**: All active models for the account

**Rationale**:
- Users configure which models they want active
- Running all active models enables comparison dashboards
- Storage is cheap, computation is fast

### 3. Event-Based vs Direct Conversion Creation

**Decision**: Event-based (require `event_id`)

**Rationale**:
- Conversions should always be tied to an event
- Event has visitor/session context
- Prevents orphaned conversions
- Maintains data integrity

### 4. Error Handling

**Decision**: Graceful degradation

- If event not found → return error, don't create conversion
- If no active models → create conversion, skip attribution
- If journey has no sessions → create conversion, attribution shows empty
- If one model fails → continue with others, log error

---

## Success Criteria

- [ ] `POST /api/v1/conversions` creates conversion and returns attribution
- [ ] Attribution credits stored in database for all active models
- [ ] Credits sum to 1.0 for each model
- [ ] Revenue credits calculated correctly when revenue provided
- [ ] Multi-tenancy enforced (can't use other account's events)
- [ ] All tests passing
- [ ] UAT verified in production

---

## Related Documentation

- [Attribution Methodology](../docs/architecture/attribution_methodology.md)
- [Channel vs UTM Attribution](channel_vs_utm_attribution.md)
- [Implementation Plan](implementation_plan_rest_api_first.md)
- [UAT Test Plan](uat_test_plan.md)

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2025-11-25 | Claude | Initial spec created based on deep review |
