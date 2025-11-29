# Streamlined SDK Architecture Specification

**Status**: Draft - Pending Implementation
**Last Updated**: 2025-11-29
**Epic**: SDK Simplification & Documentation Overhaul

---

## Executive Summary

This specification defines a streamlined 4-call SDK model for Multibuzz, simplifying the developer experience while maintaining full multi-touch attribution capabilities.

### The 4-Call Model

| Call | Purpose | When | Required |
|------|---------|------|----------|
| **init** | Initialize SDK, create session | Page/app load | Yes (first call) |
| **events** | Track journey steps | User interactions | Optional |
| **conversions** | Track business outcomes | Revenue events | Yes (for attribution) |
| **identify** | Link visitor to known user | Login/signup | Optional (enables cross-device) |

---

## Part 1: API Changes

### 1.1 Merge `alias` into `identify`

**Current State**: Two separate endpoints
- `POST /api/v1/identify` - Store traits for user_id
- `POST /api/v1/alias` - Link visitor_id to user_id

**New State**: Single unified endpoint
- `POST /api/v1/identify` - Store traits AND link visitor (if visitor_id provided)

**API Contract Change**:

```json
POST /api/v1/identify
{
  "user_id": "usr_123",
  "visitor_id": "abc123...",  // Optional - if present, creates link
  "traits": {
    "email": "jane@example.com",
    "name": "Jane Doe",
    "plan": "pro"
  }
}
```

**Behavior**:
1. If `visitor_id` provided → Create Visitor → Identity link (bidirectional in time)
2. Always update/create Identity record with traits
3. **Trigger retroactive attribution recalculation** (see section 1.2)
4. Returns success response

### 1.2 Retroactive Attribution Recalculation (Critical Feature)

**Problem**: When a user is identified on a new device, they may have sessions that occurred BEFORE existing conversions were attributed. The original attribution missed these touchpoints.

**Example Scenario**:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ BEFORE IDENTIFY                                                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│ Day 1: Desktop visit (visitor_abc)          Day 3: Mobile visit         │
│        channel: paid_search                        (visitor_xyz)         │
│        └── Session A                               channel: paid_social  │
│                                                    └── Session B         │
│                       │                                   │              │
│                       │         NOT LINKED                │              │
│                       │      (different devices)          │              │
│                       ▼                                   │              │
│              Day 5: Purchase on Desktop                   │              │
│                     visitor_abc                           │              │
│                     ┌───────────────────┐                 │              │
│                     │ Attribution:      │                 │              │
│                     │ 100% paid_search  │ ← INCOMPLETE!   │              │
│                     │ (only Session A)  │                 │              │
│                     └───────────────────┘                 │              │
│                                                                          │
├─────────────────────────────────────────────────────────────────────────┤
│ AFTER IDENTIFY (Day 7: User logs in on mobile)                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   identify("jane_123", visitor_id: "visitor_xyz")                        │
│                                                                          │
│   1. Link visitor_xyz → identity jane_123                                │
│   2. Check: Does jane_123 have existing conversions? YES (Day 5)         │
│   3. Check: Does visitor_xyz have sessions within lookback? YES (Day 3)  │
│   4. TRIGGER: Re-run attribution for Day 5 conversion                    │
│                                                                          │
│                     ┌───────────────────┐                                │
│                     │ NEW Attribution:  │                                │
│                     │ 50% paid_search   │ ← CORRECTED!                   │
│                     │ 50% paid_social   │    (Sessions A + B)            │
│                     └───────────────────┘                                │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Implementation Requirements**:

```ruby
# app/services/identity/identification_service.rb
module Identity
  class IdentificationService < ApplicationService
    def initialize(account, params)
      @account = account
      @user_id = params[:user_id]
      @visitor_id = params[:visitor_id]
      @traits = params[:traits] || {}
    end

    private

    def run
      identity = find_or_create_identity
      update_traits(identity)

      if @visitor_id.present?
        visitor = link_visitor_to_identity(identity)
        check_and_reattribute(identity, visitor)  # Retroactive attribution
      end

      success_result(identity_id: identity.prefix_id)
    end

    # Check for conversions that need re-attribution
    def check_and_reattribute(identity, newly_linked_visitor)
      # Find all conversions for this identity
      existing_conversions = account.conversions
        .where(identity: identity)
        .where('converted_at > ?', lookback_window_start)

      return if existing_conversions.empty?

      # Find sessions from newly-linked visitor
      new_visitor_sessions = newly_linked_visitor.sessions
        .where('started_at < ?', existing_conversions.maximum(:converted_at))

      return if new_visitor_sessions.empty?

      # For each conversion, check if new sessions fall within its lookback
      existing_conversions.each do |conversion|
        sessions_in_window = new_visitor_sessions
          .where('started_at >= ?', conversion.converted_at - conversion.lookback_days.days)
          .where('started_at < ?', conversion.converted_at)

        if sessions_in_window.exists?
          # Queue re-attribution job
          Attribution::RecalculationJob.perform_later(
            conversion_id: conversion.id,
            reason: 'new_visitor_linked',
            newly_linked_visitor_id: newly_linked_visitor.id
          )
        end
      end
    end

    def lookback_window_start
      # Maximum lookback we support (90 days)
      90.days.ago
    end
  end
end
```

**Re-attribution Job**:

```ruby
# app/jobs/attribution/recalculation_job.rb
module Attribution
  class RecalculationJob < ApplicationJob
    queue_as :attribution

    def perform(conversion_id:, reason:, newly_linked_visitor_id: nil)
      conversion = Conversion.find(conversion_id)

      # Log the recalculation event
      Rails.logger.info(
        "[Attribution] Recalculating conversion #{conversion.prefix_id} " \
        "reason=#{reason} new_visitor=#{newly_linked_visitor_id}"
      )

      # Re-run attribution with full journey (now includes new visitor's sessions)
      Attribution::CalculationService.new(conversion).call(force: true)

      # Update continuous aggregates
      Attribution::AggregationService.new(conversion.account).refresh
    end
  end
end
```

**API Response Enhancement**:

When identify triggers re-attribution, include in response:

```json
{
  "success": true,
  "identity_id": "idt_abc123",
  "visitor_linked": true,
  "attribution_updates": {
    "conversions_queued_for_reattribution": 2,
    "reason": "Newly linked visitor has sessions within conversion lookback windows"
  }
}
```

### 1.3 Session Endpoint Clarification

`POST /api/v1/sessions` remains unchanged but documentation clarifies:
- Called automatically by SDK on new session detection
- NOT called explicitly by developers
- SDK handles session_id generation and cookie management

---

## Part 2: SDK Specification Updates

### 2.1 SDK Types and Init Behavior

| SDK Type | Init Style | Example |
|----------|------------|---------|
| **Code-heavy** | Explicit | Ruby, Python, PHP, Node.js |
| **Platform** | Implicit | Shopify, Magento, WooCommerce |

**Explicit Init** (Ruby example):
```ruby
# config/initializers/mbuzz.rb
Mbuzz.init(
  api_key: ENV['MBUZZ_API_KEY'],
  auto_track_page_views: true,
  session_timeout: 30  # minutes
)

# In application code - init already done
Mbuzz.event('add_to_cart', product_id: 'SKU-123')
```

**Implicit Init** (Shopify example):
```
1. Merchant installs mbuzz app
2. App auto-configures with store's API key
3. Standard Shopify events auto-tracked
4. Merchant does nothing else
```

### 2.2 Required SDK Methods

All SDKs MUST implement these 4 methods:

#### `init(config)`

**Purpose**: Configure SDK and establish session

**Parameters**:
| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `api_key` | string | Yes | - | API key (`sk_live_*` or `sk_test_*`) |
| `api_url` | string | No | `https://mbuzz.co/api/v1` | API base URL |
| `auto_track_page_views` | boolean | No | `true` | Auto-track page views |
| `session_timeout` | integer | No | `30` | Session timeout in minutes |
| `debug` | boolean | No | `false` | Enable debug logging |

**Internal Behavior**:
1. Store configuration
2. Generate/retrieve `visitor_id` from cookie `_mbuzz_vid`
3. Generate/retrieve `session_id` from cookie `_mbuzz_sid`
4. If new session detected → POST to `/api/v1/sessions` (async, non-blocking)
5. Set cookies in response

**Server-Side SDKs**: Must provide middleware that calls init per-request

**Client-Side SDKs**: Called once on page load

#### `event(event_type, properties)`

**Purpose**: Track journey steps toward conversion

**Parameters**:
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `event_type` | string | Yes | Event name (e.g., `page_view`, `add_to_cart`) |
| `properties` | object | No | Custom event properties |

**Auto-enriched by SDK**:
- `visitor_id` (from cookie)
- `session_id` (from cookie)
- `url` (current page URL)
- `referrer` (document referrer)
- `timestamp` (ISO8601)

**Maps to**: `POST /api/v1/events`

**Example**:
```ruby
Mbuzz.event('add_to_cart',
  product_id: 'SKU-123',
  product_name: 'Premium Widget',
  price: 49.99,
  quantity: 2
)
```

#### `conversion(conversion_type, revenue, properties)`

**Purpose**: Track business outcomes that generate revenue

**Parameters**:
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `conversion_type` | string | Yes | Conversion name (e.g., `purchase`, `signup`) |
| `revenue` | number | No | Revenue amount |
| `currency` | string | No | Currency code (default: USD) |
| `properties` | object | No | Custom properties |

**Maps to**: `POST /api/v1/conversions`

**Returns**: Attribution breakdown (if requested)

**Example**:
```ruby
result = Mbuzz.conversion('purchase',
  revenue: 99.99,
  currency: 'USD',
  order_id: 'ORD-123',
  items: [
    { sku: 'SKU-123', name: 'Widget', price: 49.99, quantity: 2 }
  ]
)

# result[:attribution] contains model breakdowns
```

#### `identify(user_id, traits)`

**Purpose**: Link visitor to known user identity + trigger retroactive attribution

**Parameters**:
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `user_id` | string | Yes | Customer's user identifier |
| `traits` | object | No | User properties (email, name, plan, etc.) |

**Behavior**:
1. Automatically includes `visitor_id` from cookie (if present)
2. Creates Visitor → Identity link
3. Updates Identity traits
4. **Checks for conversions needing re-attribution** (see 1.2)
5. **Queues re-attribution jobs** if new sessions discovered

**Maps to**: `POST /api/v1/identify`

**Example**:
```ruby
# On signup/login
result = Mbuzz.identify(current_user.id.to_s,
  email: current_user.email,
  name: current_user.name,
  plan: current_user.plan
)

# result may include:
# {
#   success: true,
#   identity_id: "idt_abc123",
#   attribution_updates: { conversions_queued_for_reattribution: 2 }
# }
```

### 2.3 Convenience Methods

SDKs MAY implement these convenience methods:

| Method | Maps To | Description |
|--------|---------|-------------|
| `page_view(properties)` | `event('page_view', properties)` | Track page view |
| `track(event_type, properties)` | `event(event_type, properties)` | Alias for event |

### 2.4 Non-Web Integrations

For integrations without browser sessions (CRM imports, POS, call centers):

**Pattern**: Skip `init`, use `identify` + `conversion` directly

```ruby
# Backend import job
conversions.each do |conv|
  # Identify user (may or may not have prior visitor link)
  Mbuzz.identify(conv.user_id, email: conv.email)

  # Record conversion (linked via user_id)
  Mbuzz.conversion('purchase',
    revenue: conv.amount,
    order_id: conv.order_id,
    timestamp: conv.completed_at.iso8601
  )
end
```

**Attribution for non-web**:
- If user has linked visitors → Full journey attribution
- If no linked visitors → Conversion tracked, limited attribution
- Enables future visitor linking (retroactive attribution via identify)

---

## Part 3: Documentation Updates

### 3.1 Files to Update

| File | Changes |
|------|---------|
| `lib/docs/sdk/api_contract.md` | Merge alias into identify, add retroactive attribution behavior, add non-web patterns |
| `lib/specs/sdk_specification.md` | Replace with 4-method model |
| `lib/specs/identity_and_sessions_spec.md` | Add retroactive attribution section, clarify identify handles both traits + linking |
| `lib/docs/sdk/sdk_registry.md` | Update required methods, add platform SDK section |

### 3.2 New Documentation Required

#### Quick Start Guide (`app/views/docs/_getting_started.html.erb`)

**Structure**:
1. **30-second overview**: What mbuzz does (diagram)
2. **5-minute setup**: Install SDK → first conversion
3. **Core concepts**: The 4 calls explained simply
4. **Next steps**: Links to platform-specific guides

#### Platform Quick Starts

Create per-platform guides:
- `app/views/docs/platforms/_ruby.html.erb`
- `app/views/docs/platforms/_python.html.erb`
- `app/views/docs/platforms/_shopify.html.erb`
- `app/views/docs/platforms/_magento.html.erb`

#### Conceptual Guide (`app/views/docs/_concepts.html.erb`)

Non-technical explanation:
- What is multi-touch attribution?
- How visitor → session → event → conversion flows work
- Visual journey diagram
- **Cross-device attribution** and how identify enables it

---

## Part 4: Implementation Checklist

### Workflow Per Feature

Follow this DDD cycle for each feature:
1. Update docs in `app/views/docs/`
2. Write unit test (RED)
3. Write passing code (GREEN)
4. Run all tests
5. Update spec checklist
6. Git commit
7. Next feature

---

### Phase 1: Documentation (app/views/docs/)

- [x] **1.1** Add "The 4-Call Model" section at top of getting_started
- [x] **1.2** Update `init` docs (replace `configure` block)
- [x] **1.3** Update `event` docs (replace `track`)
- [x] **1.4** Update `identify` docs (merge `alias` behavior)
- [x] **1.5** Remove `alias` section from docs
- [x] **1.6** Add cross-device attribution explanation
- [x] **1.7** Update code examples (Ruby + REST API tabs)

### Phase 2: Merge Alias into Identify

**Tests first:**
- [x] **2.1** Write test: identify with visitor_id links visitor
- [x] **2.2** Write test: identify without visitor_id only stores traits
- [x] **2.3** Write test: identify returns visitor_linked: true/false

**Implementation:**
- [x] **2.4** Update `Identity::IdentificationService` to accept visitor_id (already existed)
- [x] **2.5** Update `Api::V1::IdentifyController` params (already existed)
- [x] **2.6** Add visitor linking logic to identification service (already existed)
- [x] **2.7** Update response format with visitor_linked flag

**Cleanup:**
- [x] **2.8** Run all tests, fix failures
- [ ] **2.9** Git commit: "feat(api): merge alias into identify endpoint"

### Phase 3: Retroactive Attribution

**Tests first:**
- [ ] **3.1** Write test: identify triggers reattribution when new sessions found
- [ ] **3.2** Write test: no reattribution when sessions outside lookback
- [ ] **3.3** Write test: reattribution job recalculates conversion credits

**Implementation:**
- [ ] **3.4** Create `Attribution::RecalculationJob`
- [ ] **3.5** Add reattribution check to identification service
- [ ] **3.6** Update response with attribution_updates

**Cleanup:**
- [ ] **3.7** Run all tests, fix failures
- [ ] **3.8** Git commit: "feat(attribution): retroactive recalculation on identify"

### Phase 4: Remove Alias Endpoint

- [ ] **4.1** Remove `Api::V1::AliasController`
- [ ] **4.2** Remove alias route from `routes.rb`
- [ ] **4.3** Remove alias tests
- [ ] **4.4** Run all tests, fix failures
- [ ] **4.5** Git commit: "chore(api): remove deprecated alias endpoint"

### Phase 5: Update API Contract Docs

- [ ] **5.1** Update `lib/docs/sdk/api_contract.md`
- [ ] **5.2** Update `lib/docs/sdk/sdk_registry.md`
- [ ] **5.3** Git commit: "docs(sdk): update API contract for 4-call model"

---

### Progress Tracking

| Phase | Status | Commit |
|-------|--------|--------|
| Phase 1: Documentation | Complete | - |
| Phase 2: Merge Alias | In Progress | - |
| Phase 3: Retroactive Attribution | Not Started | - |
| Phase 4: Remove Alias | Not Started | - |
| Phase 5: API Contract | Not Started | - |

---

## Related Documents

- [Homepage Visualization Spec](./homepage_visualization_spec.md) - SDK showcase + attribution animation
- [Identity & Sessions Spec](./identity_and_sessions_spec.md) - Core concepts
- [Attribution Methodology](../docs/architecture/attribution_methodology.md) - How models work

---

## Appendix A: SDK Method Comparison

### Before (Current)

```ruby
# 6 concepts to understand
Mbuzz.configure { |c| c.api_key = '...' }  # Config
Mbuzz.track('page_view', properties: {})    # Events
Mbuzz.conversion('purchase', revenue: 99)   # Conversions
Mbuzz.identify('user_123', traits: {})      # User traits
Mbuzz.alias('user_123')                     # Visitor linking
# + implicit session handling
```

### After (New)

```ruby
# 4 concepts to understand
Mbuzz.init(api_key: '...')                  # 1. Initialize
Mbuzz.event('page_view', url: '...')        # 2. Track journey
Mbuzz.conversion('purchase', revenue: 99)   # 3. Track outcome
Mbuzz.identify('user_123', email: '...')    # 4. Link identity (+ retroactive attribution)
```

**Result**: Cleaner mental model, fewer concepts, same power, smarter attribution.

---

## Appendix B: Retroactive Attribution Edge Cases

### Edge Case 1: Multiple Conversions Affected

User identified on new device → Multiple past conversions need recalculation

**Solution**: Queue each conversion separately, process in chronological order

### Edge Case 2: Conversion Already Re-attributed

Same conversion triggered for re-attribution multiple times (user links multiple devices)

**Solution**: Idempotent recalculation - always uses full current journey

### Edge Case 3: Sessions Outside All Lookback Windows

Newly-linked visitor has sessions, but all are outside lookback windows of existing conversions

**Solution**: No re-attribution triggered (correct behavior), sessions still valuable for future conversions

### Edge Case 4: High-Volume Accounts

Account with many conversions could trigger many recalculation jobs on single identify

**Solution**:
- Rate limit recalculation jobs per account
- Batch processing for accounts with >100 affected conversions
- Background priority (don't block identify response)
