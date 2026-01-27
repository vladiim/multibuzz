# Require Existing Visitor ID Specification

## Overview

This specification defines the architectural change requiring events and conversions to reference **existing visitors** rather than silently creating orphan visitors. This prevents attribution corruption from:
- Background jobs without request context
- Turbo frames losing cookie context
- SDK calls outside middleware scope

**Last Updated**: 2026-01-14
**Status**: ✅ All Phases Complete (API + Ruby + PHP SDK + Docs + CurrentAttributes + SDK E2E Tests)

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
**Status**: ✅ COMPLETE

### R5: SDK - Add Explicit visitor_id Parameter

**When**: Calling from background job or non-request context
**Do**: Allow explicit `visitor_id:` parameter that overrides context
**Status**: ✅ COMPLETE (Ruby + PHP)

### R6: Documentation - Background Job Pattern

**When**: User needs to track events from background jobs
**Do**: Document the pattern of storing visitor_id and passing explicitly
**Status**: ✅ COMPLETE (app docs), SDK READMEs pending

### R7: CurrentAttributes - Automatic Background Job Context

**When**: Rails background jobs need visitor context without database changes
**Do**: Use `ActiveSupport::CurrentAttributes` for automatic serialization into job payloads
**Status**: ✅ COMPLETE (mbuzz-ruby)

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

### Phase 2: mbuzz-php SDK Changes ✅ COMPLETE

- [x] Remove auto-generation in Context initialization
  - File: `/Users/vlad/code/m/mbuzz-php/src/Mbuzz/Context.php`
  - Change: visitorId = null if no cookie (no IdGenerator fallback)

- [x] Update `Client::track()` to accept explicit visitor_id
  - File: `/Users/vlad/code/m/mbuzz-php/src/Mbuzz/Client.php`
  - Change: Added `?string $visitorId = null` parameter

- [x] Update `Client::conversion()` to validate identifier presence
  - File: `/Users/vlad/code/m/mbuzz-php/src/Mbuzz/Client.php`
  - Change: Return false if no visitor_id AND no user_id

- [x] Update `Mbuzz::event()` facade to pass visitor_id
  - File: `/Users/vlad/code/m/mbuzz-php/src/Mbuzz/Mbuzz.php`
  - Change: Added `?string $visitorId = null` parameter

- [x] Add unit tests for explicit visitor_id requirement
  - File: `/Users/vlad/code/m/mbuzz-php/tests/Unit/ExplicitVisitorIdTest.php`
  - Tests: event/conversion without context fails, with explicit visitor_id succeeds

- [x] Update existing tests for new behavior
  - File: `/Users/vlad/code/m/mbuzz-php/tests/Unit/ContextTest.php`
  - File: `/Users/vlad/code/m/mbuzz-php/tests/Unit/ClientIntegrationTest.php`
  - Change: Tests now provide visitor cookies or explicit visitor_id

- [ ] Update README with background job documentation (deferred to Phase 3)
  - File: `/Users/vlad/code/m/mbuzz-php/README.md`
  - Change: Add "Background Jobs" section with examples

### Phase 3: multibuzz Documentation Updates ✅ COMPLETE

- [x] Update Getting Started guide with visitor_id requirement
  - File: `/Users/vlad/code/m/multibuzz/app/views/docs/_getting_started.html.erb`
  - Added "Background Jobs & Async Processing" section with:
    - Problem explanation
    - Solution pattern
    - Code examples for Ruby, PHP, Node.js, Python
    - Migration example

- [x] Add troubleshooting section for "Visitor not found" error
  - File: `/Users/vlad/code/m/multibuzz/app/views/docs/_getting_started.html.erb`
  - Added to Background Jobs section

- [ ] SDK README updates (deferred)
  - File: `/Users/vlad/code/m/mbuzz-ruby/README.md`
  - File: `/Users/vlad/code/m/mbuzz-php/README.md`

### Phase 4: CurrentAttributes for Background Jobs ✅ COMPLETE

**Approach**: Use `ActiveSupport::CurrentAttributes` instead of database storage.
Rails automatically serializes CurrentAttributes into ActiveJob payloads and restores
them when jobs execute. Zero database changes required for SDK users.

- [x] Add `Mbuzz::Current` class using ActiveSupport::CurrentAttributes
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz/current.rb`
  - Attributes: `visitor_id`, `user_id`, `ip`, `user_agent`

- [x] Middleware stores context in Current during request
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz/middleware/tracking.rb`
  - Change: `store_in_current_attributes(context, request)` in call()

- [x] Middleware resets Current after request completes
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz/middleware/tracking.rb`
  - Change: `reset_current_attributes` in ensure block

- [x] Context accessors check Current first (for background jobs)
  - File: `/Users/vlad/code/m/mbuzz-ruby/lib/mbuzz.rb`
  - Change: `current_visitor_id || RequestContext.current&.request&.env&.dig(...)`

- [x] Add unit tests for CurrentAttributes behavior
  - File: `/Users/vlad/code/m/mbuzz-ruby/test/mbuzz/current_attributes_test.rb`
  - Tests: Current stores/resets values, middleware populates Current, Mbuzz.event uses Current

- [x] Add activesupport as development dependency
  - File: `/Users/vlad/code/m/mbuzz-ruby/Gemfile`
  - Change: `gem "activesupport", ">= 7.0"`

### Phase 5: SDK Integration Test Coverage ✅ COMPLETE

**Goal**: Add end-to-end integration test coverage for background job scenarios across all SDKs.

**Architecture**: Tests are SDK-agnostic. The `SDK` env var controls which test app to run against.
The single `background_job_visitor_test.rb` works across all SDKs.

- [x] PHP SDK integration test endpoints
  - File: `/Users/vlad/code/m/multibuzz/sdk_integration_tests/apps/mbuzz_php_testapp/public/index.php`
  - Added endpoints:
    - `POST /api/background_event_no_visitor` - Event without visitor_id (should fail)
    - `POST /api/background_event_with_visitor` - Event with explicit visitor_id (should succeed)
    - `POST /api/background_conversion_no_visitor` - Conversion without visitor_id (should fail)
    - `POST /api/background_conversion_with_visitor` - Conversion with explicit visitor_id (should succeed)

- [x] Node.js SDK integration test endpoints
  - File: `/Users/vlad/code/m/multibuzz/sdk_integration_tests/apps/mbuzz_node_testapp/server.ts`
  - Added same 4 background job endpoints

- [x] Python SDK integration test endpoints
  - File: `/Users/vlad/code/m/multibuzz/sdk_integration_tests/apps/mbuzz_python_testapp/app.py`
  - Added same 4 background job endpoints

- [x] SDK-agnostic test scenario (works for all SDKs)
  - File: `/Users/vlad/code/m/multibuzz/sdk_integration_tests/scenarios/background_job_visitor_test.rb`
  - Run with: `SDK=php bundle exec ruby -Ilib scenarios/background_job_visitor_test.rb`
  - Run with: `SDK=node bundle exec ruby -Ilib scenarios/background_job_visitor_test.rb`
  - Run with: `SDK=python bundle exec ruby -Ilib scenarios/background_job_visitor_test.rb`

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

### CurrentAttributes Architecture (Recommended for Rails)

Rails automatically serializes `ActiveSupport::CurrentAttributes` into ActiveJob payloads
and restores them when jobs execute. This means visitor_id is available in background
jobs without any manual passing or database storage.

```ruby
# lib/mbuzz/current.rb
module Mbuzz
  class Current < ActiveSupport::CurrentAttributes
    attribute :visitor_id
    attribute :user_id
    attribute :ip
    attribute :user_agent
  end
end
```

**Flow**:
```
1. Request arrives
   ↓
2. Middleware captures visitor_id from cookie
   ↓
3. Middleware stores in Mbuzz::Current.visitor_id
   ↓
4. Controller enqueues background job
   ↓
5. Rails serializes Current attributes into job payload
   ↓
6. Job runs on different thread/process
   ↓
7. Rails restores Current.visitor_id before job executes
   ↓
8. Mbuzz.event/conversion reads from Current.visitor_id
   ↓
9. Works! No database changes needed.
```

### pet_resorts: No Changes Required

With CurrentAttributes, pet_resorts requires **zero code changes**. The existing
synchronous calls in controllers already work:

```ruby
# app/services/mta/track.rb - UNCHANGED
module Mta
  class Track < Base
    private

    def run
      Mbuzz.event(event, revenue: revenue, location: location)
      # visitor_id automatically available from Current or request context
    end
  end
end
```

If pet_resorts wants to move tracking to background jobs for faster response:

```ruby
# Option A: Enqueue job (CurrentAttributes handles visitor_id automatically)
class TrackEventJob < ApplicationJob
  def perform(event:, order_id:)
    order = Order.find(order_id)
    # Mbuzz::Current.visitor_id is automatically restored by Rails!
    Mbuzz.event(event, revenue: order.est_total)
  end
end

# In controller
TrackEventJob.perform_later(event: 'add_to_cart', order_id: @order.id)
```

### Alternative: Database Storage Pattern (Non-Rails or Legacy)

For non-Rails applications or when CurrentAttributes isn't available:

```ruby
# Migration
add_column :orders, :mbuzz_visitor_id, :string

# Controller - capture during request
@order.mbuzz_visitor_id = Mbuzz.visitor_id

# Background job - pass explicitly
Mbuzz.event(event, visitor_id: order.mbuzz_visitor_id)
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
| 2026-01-13 | Phase 2: mbuzz-php SDK | ✅ Complete |
| 2026-01-13 | Phase 3: Documentation | ✅ Complete |
| 2026-01-13 | Phase 4: CurrentAttributes | ✅ Complete |
| 2026-01-13 | Documentation updates | ✅ Complete |
| 2026-01-14 | mbuzz-ruby version bump to 0.7.1 | ✅ Complete |
| 2026-01-14 | Phase 5: SDK E2E Tests | ✅ Complete |

### Phase 4 Notes

Originally planned database migration approach was rejected. Instead implemented
`ActiveSupport::CurrentAttributes` which provides automatic context propagation
to background jobs with zero database changes required from SDK users.

Key insight: Rails automatically serializes CurrentAttributes into ActiveJob payloads.

### Documentation Updates (2026-01-13)

- **mbuzz-ruby README**: Added "Background Jobs" section with CurrentAttributes + explicit visitor_id patterns
- **multibuzz docs**: Updated `_getting_started.html.erb` with Solution 1 (CurrentAttributes) and Solution 2 (database)
- **Spec**: Updated to reflect CurrentAttributes approach instead of database migration

### Core Implementation Complete

Core specification is **fully implemented** and ready for production:
- ✅ API requires existing visitors (no orphan creation)
- ✅ Ruby SDK: removed fallback, added explicit visitor_id param, added CurrentAttributes
- ✅ PHP SDK: removed fallback, added explicit visitor_id param
- ✅ Documentation: getting started guide, README, spec updated
- ✅ pet_resorts: no changes needed (CurrentAttributes handles it automatically)
- ✅ mbuzz-ruby v0.7.1 released with all changes

### Phase 5: SDK E2E Tests Complete

Integration test endpoints added to all SDKs:
- ✅ PHP SDK background job endpoints
- ✅ Node.js SDK background job endpoints
- ✅ Python SDK background job endpoints

All SDKs use the same SDK-agnostic test file (`background_job_visitor_test.rb`)
controlled by the `SDK` environment variable.

---

## Related Documents

| Document | Relationship |
|----------|--------------|
| `lib/specs/1_visitor_session_tracking_spec.md` | Parent spec for visitor/session architecture |
| `lib/docs/sdk/api_contract.md` | API contract documentation |
| `lib/docs/architecture/server_side_attribution_architecture.md` | Attribution flow documentation |
