# Require Existing Visitor ID Specification

## Overview

This specification defines the architectural change requiring events and conversions to reference **existing visitors** rather than silently creating orphan visitors. This prevents attribution corruption from:
- Background jobs without request context
- Turbo frames losing cookie context
- SDK calls outside middleware scope

**Last Updated**: 2026-01-13
**Status**: Phase 0-1 Complete (API + Ruby SDK), PHP/Docs/pet_resorts pending

---

## Problem Statement

### The Orphan Visitor Problem

Server-side SDKs (Ruby, PHP) have fallback behavior that generates NEW visitor IDs when called outside request context:

```
Background Job → Mta::Track.new(event: 'purchase', order: order).call
                      ↓
              Mbuzz.event('purchase', ...)
                      ↓
              No RequestContext → fallback_visitor_id generated
                      ↓
              NEW orphan visitor created with NO attribution data
                      ↓
              Channel = "referral" (internal URL as referrer)
```

**Evidence** (production UAT Account.find(2)):
- All channels showing as "referral"
- Sessions created with internal site URLs as referrers
- Visitors created without proper UTM/channel attribution

### Root Cause Analysis

| SDK | Fallback Behavior | Creates Orphans? |
|-----|-------------------|------------------|
| **mbuzz-ruby** | `fallback_visitor_id ||= Visitor::Identifier.generate` | **YES** |
| **mbuzz-php** | `IdGenerator::generate()` in Context | **YES** |
| **mbuzz-node** | Returns `undefined`, validation fails → `false` | No |
| **mbuzz-python** | Returns `None`, validation fails → `TrackResult(success=False)` | No |
| **mbuzz-shopify** | Client-side, always has browser context | No |

### The Correct Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    VISITOR CREATION                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  POST /api/v1/sessions                                          │
│    ├─ Creates visitor with device_fingerprint                   │
│    ├─ Creates session with UTM parameters                       │
│    ├─ Derives channel from UTM/referrer                         │
│    └─ Returns visitor_id for subsequent calls                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    EVENTS & CONVERSIONS                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  POST /api/v1/events                                            │
│  POST /api/v1/conversions                                       │
│    ├─ REQUIRES existing visitor_id                              │
│    ├─ Rejects if visitor not found                              │
│    └─ Never creates new visitors                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Requirements

### R1: API - Require Existing Visitor

**When**: Processing event or conversion with unknown visitor_id
**Do**: Return error "Visitor not found" instead of creating new visitor
**Status**: ✅ COMPLETE

### R2: API - Backward Compatibility for Fingerprint

**When**: Session exists with `device_fingerprint: nil` (pre-fingerprinting)
**Do**: Match sessions with nil fingerprint for existing visitors
**Status**: ✅ COMPLETE

### R3: SDK - Remove Silent Fallback (Ruby)

**When**: `Mbuzz.event()` or `Mbuzz.conversion()` called outside request context
**Do**: Raise error or return failure instead of generating orphan visitor_id
**Status**: ✅ COMPLETE

### R4: SDK - Remove Silent Fallback (PHP)

**When**: `$mbuzz->track()` or `$mbuzz->conversion()` called outside request context
**Do**: Return false instead of generating orphan visitor_id
**Status**: Pending

### R5: SDK - Add Explicit visitor_id Parameter

**When**: Calling from background job or non-request context
**Do**: Allow explicit `visitor_id:` parameter that overrides context
**Status**: ✅ COMPLETE (Ruby), Pending (PHP)

### R6: Documentation - Background Job Pattern

**When**: User needs to track events from background jobs
**Do**: Document the pattern of storing visitor_id and passing explicitly
**Status**: Pending

### R7: Client Implementation - Store visitor_id

**When**: Processing orders/events that may be handled in background jobs
**Do**: Store `mbuzz_visitor_id` on the record when created in request context
**Status**: Pending (pet_resorts)

---

## Development Workflow

### Per-Feature Cycle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        FEATURE DEVELOPMENT CYCLE                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. SDK INTEGRATION TEST (RED)                                              │
│     └─ Start in ./sdk_integration_tests/                                    │
│     └─ Write failing test against target SDK + API                          │
│     └─ Proves the feature doesn't work yet                                  │
│                                                                              │
│  2. UNIT TESTS (RED)                                                        │
│     └─ SDK: mbuzz-{lang}/test/*                                             │
│     └─ Write failing unit tests for new behavior                            │
│                                                                              │
│  3. IMPLEMENTATION                                                          │
│     └─ SDK: mbuzz-{lang}/lib/ or src/                                       │
│     └─ Minimal code to pass tests                                           │
│                                                                              │
│  4. UNIT TESTS (GREEN)                                                      │
│     └─ Run SDK test suite, all tests pass                                   │
│                                                                              │
│  5. SDK INTEGRATION TEST (GREEN)                                            │
│     └─ Run ./sdk_integration_tests/ against local                           │
│     └─ Proves feature works end-to-end                                      │
│                                                                              │
│  6. UPDATE SPEC                                                             │
│     └─ Mark checkbox [x] complete in this spec                              │
│     └─ Add any learnings or changes                                         │
│                                                                              │
│  7. GIT COMMIT                                                              │
│     └─ Commit with Sydney time: 2026-01-12 20:00-21:00 +11:00               │
│     └─ Format: feat(scope): description                                     │
│                                                                              │
│  8. NEXT FEATURE                                                            │
│     └─ Repeat steps 1-7                                                     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### SDK Development Order

```
PHASE 1: mbuzz-ruby
  └─ ./sdk_integration_tests/ruby/ (integration tests)
  └─ /Users/vlad/code/m/mbuzz-ruby/test/ (unit tests)
  └─ /Users/vlad/code/m/mbuzz-ruby/lib/mbuzz.rb (implementation)

PHASE 2: mbuzz-php
  └─ ./sdk_integration_tests/php/ (integration tests)
  └─ /Users/vlad/code/m/mbuzz-php/tests/ (unit tests)
  └─ /Users/vlad/code/m/mbuzz-php/src/Mbuzz/ (implementation)

PHASE 3: Documentation
  └─ /Users/vlad/code/m/multibuzz/app/views/docs/
  └─ /Users/vlad/code/m/multibuzz/app/views/onboarding/
  └─ SDK READMEs

PHASE 4: pet_resorts
  └─ /Users/vlad/code/pet_resorts/
```

### Commit Convention

All commits use **2026-01-12** between **8pm-9pm Sydney time** (AEDT +11:00):

```bash
GIT_AUTHOR_DATE="2026-01-12T20:XX:XX+11:00" \
GIT_COMMITTER_DATE="2026-01-12T20:XX:XX+11:00" \
git commit -m "feat(sdk): description"
```

### Verification Commands

```bash
# 1. SDK Integration Tests (start here)
cd /Users/vlad/code/m/multibuzz/sdk_integration_tests
./run_ruby_tests.sh   # or relevant SDK

# 2. SDK Unit Tests
cd /Users/vlad/code/m/mbuzz-ruby && bundle exec rake test
cd /Users/vlad/code/m/mbuzz-php && ./vendor/bin/phpunit

# 3. API Tests (if API changes needed)
cd /Users/vlad/code/m/multibuzz && bin/rails test
```

---

## Implementation Checklist

### Phase 0: API Changes ✅ COMPLETE

- [x] `Visitors::LookupService` returns error instead of creating visitors
  - File: `app/services/visitors/lookup_service.rb`
  - Change: `visitor_not_found_error` instead of `create_visitor_result`

- [x] `Sessions::ResolutionService` matches nil fingerprints for backward compat
  - File: `app/services/sessions/resolution_service.rb`
  - Change: `.where(device_fingerprint: [device_fingerprint, nil])`

- [x] Update all affected tests
  - `test/services/visitors/lookup_service_test.rb`
  - `test/services/events/processing_service_test.rb`
  - `test/services/events/ingestion_service_test.rb`
  - `test/jobs/events/processing_job_test.rb`
  - `test/controllers/api/v1/events_controller_test.rb`
  - `test/integration/event_tracking_flow_test.rb`
  - `test/integration/concurrent_events_dedup_test.rb`

### Phase 1: mbuzz-ruby SDK Changes ✅ COMPLETE

- [x] Remove `fallback_visitor_id` method
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz.rb`
  - Change: Removed entire method, visitor_id returns nil without context

- [x] Update `visitor_id` method to return nil when no context
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz.rb`
  - Change: Removed `|| fallback_visitor_id` fallback

- [x] Add explicit `visitor_id:` parameter to `event()` method
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz.rb`
  - Change: Added `visitor_id: nil` parameter, returns false if no identifier

- [x] Add explicit `visitor_id:` parameter to `conversion()` method
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz.rb`
  - Change: Added `visitor_id: nil` parameter, returns false if no identifier

- [x] Return false when no identifier available (visitor_id or user_id)
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz.rb`
  - Change: Early return `false` in event() and conversion()

- [x] Add unit tests for explicit visitor_id requirement
  - File: `/Users/vlad/code/m/mbuzz-ruby/test/mbuzz/explicit_visitor_id_test.rb`
  - Tests: event/conversion without context fails, with explicit visitor_id succeeds

- [x] Add integration test endpoints for background job simulation
  - File: `/Users/vlad/code/m/multibuzz/sdk_integration_tests/apps/mbuzz_ruby_testapp/app.rb`
  - Endpoints: background_event_no_visitor, background_event_with_visitor, etc.

- [x] Add integration tests for background job scenarios
  - File: `/Users/vlad/code/m/multibuzz/sdk_integration_tests/scenarios/background_job_visitor_test.rb`

- [x] Update existing tests for new behavior
  - File: `/Users/vlad/code/m/mbuzz-ruby/test/test_mbuzz.rb` - Removed fallback tests
  - File: `/Users/vlad/code/m/mbuzz-ruby/test/mbuzz/event_integration_test.rb` - Added visitor_id to MockRequest

- [ ] Update README with background job documentation (deferred to Phase 3)
  - File: `/Users/vlad/code/m/mbuzz-ruby/README.md`
  - Change: Add "Background Jobs" section with examples

### Phase 2: mbuzz-php SDK Changes

- [ ] Remove auto-generation in Context initialization
  - File: `/Users/vlad/code/m/mbuzz-php/src/Mbuzz/Context.php`
  - Lines: 49-51
  - Change: Set `visitorId` to `null` if no cookie, don't generate

- [ ] Update `Client::track()` to accept explicit visitor_id
  - File: `/Users/vlad/code/m/mbuzz-php/src/Mbuzz/Client.php`
  - Lines: 72-79
  - Change: Add `$visitorId` parameter option

- [ ] Update `Client::conversion()` to validate identifier presence
  - File: `/Users/vlad/code/m/mbuzz-php/src/Mbuzz/Client.php`
  - Lines: 115-126
  - Change: Return false if no identifier available

- [ ] Add warning when visitor_id is null
  - File: `/Users/vlad/code/m/mbuzz-php/src/Mbuzz/Client.php`
  - Change: Log warning via configured logger

- [ ] Update tests for new behavior
  - File: `/Users/vlad/code/m/mbuzz-php/tests/Unit/ClientTest.php`
  - File: `/Users/vlad/code/m/mbuzz-php/tests/Unit/ContextTest.php`
  - Change: Test null visitor_id handling, explicit param

- [ ] Update README with background job documentation
  - File: `/Users/vlad/code/m/mbuzz-php/README.md`
  - Change: Add "Background Jobs" section with examples

### Phase 3: multibuzz Documentation Updates

- [ ] Update Getting Started guide with visitor_id requirement
  - File: `/Users/vlad/code/m/multibuzz/app/views/docs/_getting_started.html.erb`
  - Section: After "Sessions" section (~line 245)
  - Change: Add "Background Jobs & Async Processing" section

- [ ] Update server-side install partial with explicit visitor_id examples
  - File: `/Users/vlad/code/m/multibuzz/app/views/onboarding/_install_server_side.html.erb`
  - Change: Show storing and passing visitor_id

- [ ] Add troubleshooting section for "Visitor not found" error
  - File: `/Users/vlad/code/m/multibuzz/app/views/docs/_getting_started.html.erb`
  - Section: New "Troubleshooting" section
  - Change: Document common causes and solutions

### Phase 4: pet_resorts Implementation Fix

- [ ] Add `mbuzz_visitor_id` column to orders table
  - File: `/Users/vlad/code/pet_resorts/db/migrate/XXXXXX_add_mbuzz_visitor_id_to_orders.rb`
  - Change: `add_column :orders, :mbuzz_visitor_id, :string`

- [ ] Store visitor_id when order created in request context
  - File: `/Users/vlad/code/pet_resorts/app/controllers/orders_controller.rb`
  - Change: `order.mbuzz_visitor_id = Mbuzz.visitor_id` on create

- [ ] Update `Mta::Base` to accept visitor_id parameter
  - File: `/Users/vlad/code/pet_resorts/app/services/mta/base.rb`
  - Change: Add `visitor_id:` to initialize, pass to Mbuzz calls

- [ ] Update `Mta::Track` to pass visitor_id
  - File: `/Users/vlad/code/pet_resorts/app/services/mta/track.rb`
  - Change: `Mbuzz.event(event, visitor_id: visitor_id, ...)`

- [ ] Update `Mta::Convert` to pass visitor_id
  - File: `/Users/vlad/code/pet_resorts/app/services/mta/convert.rb`
  - Change: `Mbuzz.conversion(event, visitor_id: visitor_id, ...)`

- [ ] Update all Mta service call sites to pass visitor_id
  - File: `/Users/vlad/code/pet_resorts/app/controllers/order_items_controller.rb`
  - File: `/Users/vlad/code/pet_resorts/app/controllers/flow/booking/reviews_controller.rb`
  - Change: Pass `visitor_id: order.mbuzz_visitor_id`

---

## Technical Design Details

### mbuzz-ruby: New Method Signatures

**Current** (`lib/mbuzz.rb:82-105`):
```ruby
def self.event(event_type, identifier: nil, **properties)
  Client.track(
    visitor_id: visitor_id,  # Uses fallback if no context
    ...
  )
end
```

**Proposed**:
```ruby
def self.event(event_type, visitor_id: nil, identifier: nil, **properties)
  resolved_visitor_id = visitor_id || self.visitor_id

  if resolved_visitor_id.nil? && user_id.nil?
    config.logger&.warn("[mbuzz] No visitor_id available - call from request context or pass explicit visitor_id")
    return false
  end

  Client.track(
    visitor_id: resolved_visitor_id,
    ...
  )
end
```

### mbuzz-ruby: Remove Fallback

**Current** (`lib/mbuzz.rb:65-71`):
```ruby
def self.visitor_id
  RequestContext.current&.request&.env&.dig(ENV_VISITOR_ID_KEY) || fallback_visitor_id
end

def self.fallback_visitor_id
  @fallback_visitor_id ||= Visitor::Identifier.generate
end
```

**Proposed**:
```ruby
def self.visitor_id
  RequestContext.current&.request&.env&.dig(ENV_VISITOR_ID_KEY)
end

# Remove fallback_visitor_id method entirely
```

### mbuzz-php: Context Changes

**Current** (`src/Mbuzz/Context.php:49-51`):
```php
$this->visitorId = $cookies->getVisitorId() ?? IdGenerator::generate();
```

**Proposed**:
```php
$this->visitorId = $cookies->getVisitorId();  // null if no cookie
```

### mbuzz-php: Client Changes

**Current** (`src/Mbuzz/Client.php:72-79`):
```php
$request = new TrackRequest(
    eventType: $eventType,
    visitorId: $this->context->getVisitorId(),
    ...
);
```

**Proposed**:
```php
public function track(string $eventType, array $properties = [], ?string $visitorId = null): bool
{
    $resolvedVisitorId = $visitorId ?? $this->context->getVisitorId();

    if ($resolvedVisitorId === null && $this->context->getUserId() === null) {
        $this->logger?->warning('[mbuzz] No visitor_id available');
        return false;
    }

    $request = new TrackRequest(
        eventType: $eventType,
        visitorId: $resolvedVisitorId,
        ...
    );
}
```

### Documentation: Background Jobs Section

Add to `app/views/docs/_getting_started.html.erb` after Sessions section:

**Content outline**:
1. **Why visitor_id is required** - Attribution needs the visitor created via /sessions
2. **The problem with background jobs** - No request context = no visitor_id
3. **Solution: Store visitor_id early** - When order/record created in request context
4. **Pass visitor_id explicitly** - Show code example for each SDK
5. **Common errors** - "Visitor not found" means missing visitor_id

### pet_resorts: Migration Pattern

```ruby
# db/migrate/XXXXXX_add_mbuzz_visitor_id_to_orders.rb
class AddMbuzzVisitorIdToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :mbuzz_visitor_id, :string
    add_index :orders, :mbuzz_visitor_id
  end
end
```

### pet_resorts: Controller Pattern

```ruby
# app/controllers/orders_controller.rb
def create
  @order = Order.new(order_params)
  @order.mbuzz_visitor_id = Mbuzz.visitor_id  # Capture while in request context

  if @order.save
    # ... success handling
  end
end
```

### pet_resorts: Service Pattern

```ruby
# app/services/mta/base.rb
module Mta
  class Base
    attr_reader :event, :order, :visitor_id

    def initialize(event:, order:, visitor_id: nil)
      @event = event
      @order = order
      @visitor_id = visitor_id || order&.mbuzz_visitor_id
    end
  end
end

# app/services/mta/track.rb
module Mta
  class Track < Base
    private

    def run
      Mbuzz.event(event, visitor_id: visitor_id, revenue: revenue, location: location)
    end
  end
end
```

---

## SDK Comparison Summary

| SDK | Current Behavior | Required Change | Priority |
|-----|------------------|-----------------|----------|
| **mbuzz-ruby** | Generates orphan visitor_id | Remove fallback, add explicit param | **HIGH** |
| **mbuzz-php** | Generates orphan visitor_id | Remove fallback, add explicit param | **HIGH** |
| **mbuzz-node** | Returns undefined → fails gracefully | None (already correct) | N/A |
| **mbuzz-python** | Returns None → fails gracefully | None (already correct) | N/A |
| **mbuzz-shopify** | Client-side with browser context | None (always has context) | N/A |

---

## Testing Scenarios

| Scenario | Expected Behavior |
|----------|-------------------|
| Event with valid visitor_id | Accepted, event created |
| Event with unknown visitor_id | Rejected, "Visitor not found" error |
| Event from background job without visitor_id | Rejected, warning logged |
| Event from background job with explicit visitor_id | Accepted |
| Conversion with event_id only | Accepted (uses event's visitor) |
| Conversion without any identifier | Rejected |
| Session creation (new visitor) | Accepted, visitor created with attribution |

---

## Verification Commands

```bash
# API tests
cd /Users/vlad/code/m/multibuzz && bin/rails test

# SDK tests (after changes)
cd /Users/vlad/code/m/mbuzz-ruby && bundle exec rake test
cd /Users/vlad/code/m/mbuzz-php && ./vendor/bin/phpunit

# Integration verification
cd /Users/vlad/code/m/multibuzz && bin/rails test test/integration/
```

---

## Rollback Plan

1. **If SDK changes break existing integrations**:
   - Revert to fallback behavior temporarily
   - Add deprecation warning instead of hard failure
   - Give users time to update their code

2. **API changes are backward compatible**:
   - Sessions endpoint still creates visitors
   - Events with valid visitor_id continue to work
   - Only affects events with unknown visitor_id

---

## Progress Log

| Date | Item | Status |
|------|------|--------|
| 2026-01-13 | Spec created | Complete |
| 2026-01-13 | Phase 0: API changes | ✅ Complete |
| 2026-01-13 | Phase 1: mbuzz-ruby SDK | ✅ Complete |
| TBD | Phase 2: mbuzz-php SDK | Pending |
| TBD | Phase 3: Documentation | Pending |
| TBD | Phase 4: pet_resorts fix | Pending |

---

## Related Documents

| Document | Relationship |
|----------|--------------|
| `lib/specs/1_visitor_session_tracking_spec.md` | Parent spec for visitor/session architecture |
| `lib/docs/sdk/api_contract.md` | API contract documentation |
| `lib/docs/architecture/server_side_attribution_architecture.md` | Attribution flow documentation |
