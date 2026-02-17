# Cross-Visit Journey Stitching Specification

**Date:** 2026-02-17
**Priority:** P0
**Status:** Draft
**Branch:** `feature/journey-stitching`

---

## Summary

The "Avg Days to Convert" metric reads 0.0 across all accounts. Investigation reveals three independent failures that compound to break multi-day journey tracking entirely:

1. **Silent attribution failures (40% of conversions)** — `AttributionCalculationJob` discards the service result. When Markov/Shapley algorithms blow up on high-session visitors (O(2^n) complexity), `ApplicationService` catches the exception, `update_journey_session_ids` never executes, and `journey_session_ids` stays `[]`. Zero logging, zero observability.

2. **SDK `user_id` shadowing bug (all SDKs)** — `Mbuzz.conversion()` in the Ruby SDK has a `user_id: nil` parameter that shadows the `self.user_id` class method. Even after `identify()` stores the user_id in request context, `conversion()` can't see it. Node and Python have a different variant: `identify()` never writes user_id back to context. Only PHP works correctly. Result: 0% of conversions have `identity_id` set.

3. **No cross-device attribution at conversion time** — `AttributionCalculationService` always uses single-visitor `JourneyBuilder`, never `CrossDeviceCalculator`. Even if identity were set, sessions from other identity-linked visitors would be invisible.

---

## Current State

### Production Evidence (Account 2, 2026-02-17)

| Metric | Value |
|--------|-------|
| Total conversions (60d) | 2,726 |
| Empty `journey_session_ids` | 1,091 (40.1%) |
| Conversions with `identity_id` | 0 (0.0%) |
| Identities in account | 8,757 |
| Identities with 2+ visitors | 732 |
| Device fingerprints with 2+ visitors | 22,797 |
| Dashboard "Avg Days to Convert" | 0.0 |

Two distinct conversion populations:

| | Pattern A (60%) | Pattern B (40%) |
|-|-----------------|-----------------|
| `journey_session_ids` | Populated | `[]` (empty) |
| Visitor sessions | 1-3 | 125-139 |
| Days to convert | 0.0-17.7 | 6.8-49.8 (invisible) |
| Root cause | Short same-day journeys | Attribution job silently failed |

**Pattern B contains the multi-day journeys.** These conversions have visitors with 49+ days of session history, but the attribution job failed silently, leaving `journey_session_ids` empty. They're excluded from all dashboard metrics.

### Failure Chain: Silent Attribution Failures

```
1. Conversion created → journey_session_ids: []
2. AttributionCalculationJob fires
3. AttributionCalculationService iterates all 8 active models
4. Heuristic models succeed (first_touch, last_touch, linear, etc.)
   → AttributionCredit records persisted to DB
5. Shapley hits O(2^n) power_set computation → exception
6. Exception propagates up through each_with_object loop
7. ApplicationService catches StandardError → returns { success: false }
8. update_journey_session_ids NEVER EXECUTES
9. Job discards the error hash, completes "successfully"
10. journey_session_ids stays []
11. Orphaned credits exist but conversion invisible to dashboard
12. ConversionPathsQuery excludes this conversion → degrades Markov/Shapley training data
```

**Source:** `app/services/attribution/algorithms/shapley_value.rb:52-60` — `power_set` is recursive O(2^n) where n = unique channels across all account conversion paths. `app/services/application_service.rb:2-10` catches `StandardError` with zero logging. `app/jobs/conversions/attribution_calculation_job.rb:7-9` discards the return value.

### Failure Chain: SDK `user_id` Shadowing

**Ruby SDK** (`mbuzz-0.7.3/lib/mbuzz.rb`):

```ruby
# event() — CORRECT: no user_id param, resolves from self.user_id
def self.event(event_type, visitor_id: nil, identifier: nil, **properties)
  resolved_user_id = user_id  # calls self.user_id → reads Current/env context
  ...
end

# conversion() — BUG: user_id param shadows self.user_id
def self.conversion(conversion_type, visitor_id: nil, revenue: nil, user_id: nil, ...)
  # user_id here is the nil parameter, NOT self.user_id
  Client.conversion(user_id: user_id, ...)  # always nil unless explicitly passed
end
```

**All SDKs affected:**

| SDK | `conversion()` resolves user_id from context | `identify()` stores user_id in context | "identify → convert" works? |
|-----|------|------|------|
| **Ruby** | NO — parameter shadows class method | Partially (middleware reads session, not identify call) | **NO** |
| **Node** | YES (`options.userId ?? ctx?.userId`) | **NO** — context is `readonly`, identify only calls API | **NO** |
| **Python** | YES (`user_id or ctx.user_id`) | **NO** — identify only calls API, never writes context | **NO** |
| **PHP** | YES (`$options['user_id'] ?? $this->context->getUserId()`) | **YES** — `$this->context->setUserId($userId)` | **YES** |

**Customer impact (pet_resorts):** App calls `Mbuzz.identify(user.prefix_id)` after login, then `Mbuzz.conversion("estimate_accepted", revenue: amount, properties: { location: name })` — no `user_id:` passed. Identity exists (8,757 records) but never reaches the conversion. 0% of conversions have `identity_id`.

### Failure Chain: No Cross-Device Attribution

`AttributionCalculationService` (line 94-98) always uses `Attribution::Calculator` → `JourneyBuilder(visitor:)`, which queries sessions for a single visitor. `CrossDeviceCalculator` → `CrossDeviceJourneyBuilder(identity:)` exists and works, but is only used by `ReattributionService` and `RerunService` — never at conversion time.

---

## Proposed Solution

Six targeted fixes across three codebases (mbuzz server, Ruby SDK, E2E tests), plus equivalent fixes for Node/Python SDKs. No new classes needed — this is a wiring and resilience problem.

### Data Flow (Proposed)

```
User logs in → identify() called
  → Identity created/found, visitor linked
  → SDK stores user_id in context  ← FIX (SDK)

User converts → conversion() called
  → SDK resolves user_id from context  ← FIX (SDK)
  → Server creates Conversion with identity_id  ← NOW WORKS

AttributionCalculationJob fires
  → Service resolves identity from conversion  ← FIX (server)
  → Uses CrossDeviceCalculator when identity present
    → Finds ALL sessions across ALL identity-linked visitors
  → Each model calculated independently; failures isolated  ← FIX (resilience)
  → journey_session_ids = ALL touchpoints from builder  ← FIX (server)
  → Days to convert: reflects full multi-day journey ✓
```

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| **Identity present at conversion time** | `conversion.identity.present?` | `CrossDeviceCalculator` with `CrossDeviceJourneyBuilder` — full multi-visitor journey |
| **No identity at conversion time** | `identity.nil?` | Fall back to `Calculator` with `JourneyBuilder` — single-visitor (no regression) |
| **Identity linked after conversion** | `identify()` called post-conversion | `ReattributionService` handles this (already works) |
| **Single model fails (e.g. Shapley)** | Algorithm raises exception | Isolate failure to that model; other models' credits + `journey_session_ids` still saved |
| **All models fail** | Every algorithm raises | `journey_session_ids` stays `[]`, error logged, job reports failure |
| **High session count (100+)** | Visitor with many sessions | Heuristic models succeed; Shapley/Markov failures isolated |
| **Inherited acquisition attribution** | `conversion.inherit_acquisition?` | Copy `journey_session_ids` from acquisition conversion |
| **SDK identify → convert flow** | Same request, no explicit user_id | SDK resolves user_id from context; server sets identity_id on conversion |

---

## Implementation Tasks

### Phase 1: Attribution Resilience (fixes the 40%) ✅

- [x] **1.1** Isolate per-model failures in `AttributionCalculationService#calculate_fresh_attribution` — `calculate_model_safely` wraps each model in rescue, logs error, returns `[]`
- [x] **1.2** `store_journey_session_ids` derives from `touchpoints` (JourneyBuilder), not credits — computed once before model iteration
- [x] **1.3** `inherit_journey_session_ids` copies acquisition conversion's journey to inheriting conversion
- [x] **1.4** Error logging via `Rails.logger.error("[Attribution] #{model.name} failed for conversion #{id}: #{message}")`
- [x] **1.5** Test: one model fails, other models' credits still persisted
- [x] **1.6** Test: `journey_session_ids` populated even when one model fails
- [x] **1.7** Test: inherited attribution path populates `journey_session_ids`
- [x] **1.8** Test: `journey_session_ids` contains ALL touchpoint sessions (5), not just credited (2)

### Phase 2: Identity-Aware Attribution (fixes cross-device)

- [ ] **2.1** In `AttributionCalculationService`, resolve identity: prefer `conversion.identity`, fall back to `conversion.visitor.identity`
- [ ] **2.2** When identity present, use `CrossDeviceCalculator`; otherwise fall back to `Calculator`
- [ ] **2.3** In `Shopify::Handlers::OrderPaid#create_conversion`, add `identity_id: visitor.identity&.id`
- [ ] **2.4** Write test: uses `CrossDeviceCalculator` when conversion has identity
- [ ] **2.5** Write test: falls back to single-visitor `Calculator` when no identity
- [ ] **2.6** Write test: cross-device journey includes sessions from multiple visitors
- [ ] **2.7** Write test: OrderPaid sets identity_id when visitor has identity

### Phase 3: SDK `user_id` Resolution (fixes all SDKs)

#### 3A: Ruby SDK

- [ ] **3A.1** Fix `Mbuzz.conversion` shadowing: resolve `user_id` from context when not explicitly passed (`resolved_user_id = user_id || self.user_id`)
- [ ] **3A.2** `identify()` should store user_id in `Current.user_id` for same-request access (currently only middleware sets this from session)
- [ ] **3A.3** Write unit test: `conversion()` picks up user_id after `identify()` in same request
- [ ] **3A.4** Write unit test: explicit `user_id:` parameter still takes precedence over context

#### 3B: Node SDK

- [ ] **3B.1** `identify()` should write `userId` back to the `AsyncLocalStorage` context after successful API call
- [ ] **3B.2** Make `RequestContext.userId` mutable (currently `readonly`)
- [ ] **3B.3** Write unit test: `conversion()` picks up userId after `identify()` in same request

#### 3C: Python SDK

- [ ] **3C.1** `identify()` should update the context's `user_id` after successful API call
- [ ] **3C.2** Write unit test: `conversion()` picks up user_id after `identify()` in same request

#### 3D: PHP SDK (reference implementation — no changes needed)

- [ ] **3D.1** Verify existing behavior: `identify()` calls `$this->context->setUserId()`, `conversion()` reads it back
- [ ] **3D.2** Write unit test confirming this if not already covered

### Phase 4: E2E Tests — "Identify Then Convert" Flow

- [ ] **4.1** Add E2E scenario: `identify_then_convert_test.rb` — calls `identify(user_id)` then `conversion(type, revenue:)` WITHOUT explicit `user_id`, verifies server-side conversion has `identity_id` set
- [ ] **4.2** Run against Ruby test app (port 4001)
- [ ] **4.3** Run against Node test app (port 4002)
- [ ] **4.4** Run against Python test app (port 4003)
- [ ] **4.5** Run against PHP test app (port 4004)
- [ ] **4.6** Verify `journey_session_ids` populated with cross-device sessions when identity has multiple visitors

### Phase 5: Backfill Production Data

- [ ] **5.1** Write rake task to recompute `journey_session_ids` for all conversions with empty arrays
- [ ] **5.2** Task uses `CrossDeviceJourneyBuilder` when visitor has identity, `JourneyBuilder` otherwise
- [ ] **5.3** Re-run failed attribution for conversions with orphaned credits (credits exist but `journey_session_ids` empty)
- [ ] **5.4** Log progress and stats (total, updated, skipped, errors)

---

## Testing Strategy

### Unit Tests (mbuzz server)

| Test | File | Verifies |
|------|------|----------|
| Model failure isolation | `test/services/conversions/attribution_calculation_service_test.rb` | One model fails, others' credits still persisted |
| Journey stored on partial failure | Same | `journey_session_ids` populated from touchpoints even when Shapley fails |
| Full touchpoints stored | Same | Array includes all journey sessions, not just credited ones |
| Inherited attribution journey | Same | `journey_session_ids` set even for inherited credits |
| Cross-device when identity present | Same | Uses `CrossDeviceCalculator`, credits span multiple visitors |
| Single-visitor fallback | Same | No regression when no identity |
| OrderPaid sets identity_id | `test/services/shopify/handlers/order_paid_test.rb` | Conversion has `identity_id` from visitor's identity |
| TotalsQuery with multi-day journey | `test/services/dashboard/queries/totals_query_test.rb` | Existing tests validate — no changes needed |

### Unit Tests (SDKs)

| Test | SDK | Verifies |
|------|-----|----------|
| conversion resolves user_id from context | Ruby | After identify(), conversion sends user_id without explicit param |
| explicit user_id takes precedence | Ruby | `Mbuzz.conversion("x", user_id: "explicit")` uses "explicit", not context |
| identify stores userId in context | Node | After identify(), context.userId is set |
| identify stores user_id in context | Python | After identify(), context.user_id is set |
| PHP end-to-end (reference) | PHP | identify → conversion works (confirm existing behavior) |

### E2E Integration Tests

| Test | File | Verifies |
|------|------|----------|
| Identify then convert (all SDKs) | `sdk_integration_tests/scenarios/identify_then_convert_test.rb` | Conversion created with `identity_id` set, without explicit `user_id` in conversion call |
| Cross-device journey stitching | `sdk_integration_tests/scenarios/cross_device_journey_test.rb` | Conversion's `journey_session_ids` includes sessions from multiple visitors under same identity |

### Manual QA

1. Deploy SDK fixes to pet_resorts staging
2. Log in as user → triggers `identify()`
3. Complete booking → triggers `conversion("estimate_accepted")`
4. In mbuzz console: verify `conversion.identity_id` is set
5. Dashboard "Avg Days to Convert" shows non-zero values after backfill

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Isolate per-model failures | Rescue inside the loop, not outside | One bad algorithm shouldn't wipe out all attribution. Credits from successful models are valid. |
| Derive journey from touchpoints, not credits | Compute touchpoints once from builder, store all session IDs | `journey_session_ids` feeds "Avg Days" and "Avg Visits" — journey metrics, not attribution metrics. |
| Resolve user_id in SDK conversion() | Fall back to context, like event() does | The identify → convert flow is the primary use case. Requiring explicit user_id is a foot-gun. |
| identify() writes to context | Store user_id in context after successful API call | Same-request identify → convert must work. PHP already does this correctly. |
| Backfill via rake task | Recompute journey + re-run failed attribution | 40% of conversions have orphaned credits. Targeted repair is faster than full rerun. |

---

## Definition of Done

- [ ] All implementation tasks completed
- [ ] Unit tests pass (server + all SDKs)
- [ ] E2E "identify then convert" test passes for Ruby, Node, Python, PHP
- [ ] No regressions in existing attribution behavior
- [ ] Backfill task run on production
- [ ] Dashboard "Avg Days to Convert" shows non-zero values
- [ ] SDK gems/packages published with fix (Ruby 0.7.4+, Node, Python)
- [ ] Spec updated with final state and moved to `old/`

---

## Out of Scope

- **Safari ITP / cookie persistence** — larger architecture change (server-side cookies). Identity linking works independently of cookie persistence.
- **Shapley O(2^n) optimization** — isolating failures is the immediate fix. Algorithmic optimization (capping subsets, caching coalition values) is a separate performance spec.
- **Fingerprint-based visitor merging at conversion time** — production data shows top fingerprints have 3,000+ visitors (bots/shared IPs). Fingerprint stitching would pollute real journeys.
- **`TotalsQuery` changes** — the LATERAL join is correct. The issue is entirely upstream data quality.
- **`ReattributionService` changes** — already uses `CrossDeviceCalculator`, already works when identity links happen post-conversion.
