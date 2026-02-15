# API Data Integrity Fixes Specification

**Date:** 2026-02-09
**Priority:** P0
**Status:** Complete
**Branch:** `feature/e1s4-content`

---

## Summary

End-to-end review of the sGTM integration revealed 5 server-side data corruption risks that affect ALL API clients. These range from silent data loss (revenue=0 becomes NULL) to race conditions producing duplicate attribution credits.

---

## Current State

### 1. Revenue=0 silently becomes NULL

`Conversions::TrackingService#normalized_revenue` (line 151) treats zero as invalid via `revenue.to_f.zero?`. `Conversion::Validations` (line 10) enforces `greater_than: 0`. Together, $0 revenue is impossible to store — free-tier signups, $0 trials, and complimentary orders lose revenue data.

### 2. Traits overwrite instead of merge

`Identities::IdentificationService#persist_identity` (line 38) does `identity.traits = traits` — a full replacement. If identify is called twice with different trait subsets, the first call's traits are deleted.

### 3. Billing block returns 202 with silent flag

`Events::IngestionService#billing_blocked_result` (line 105) returns `{ billing_blocked: true }` inside a normal response. `EventsController` renders this as 202. SDKs that don't inspect the `billing_blocked` key silently lose events.

### 4. No conversion idempotency

`Conversions::TrackingService#conversion` (line 108) calls `Conversion.create!` on every request. Network retries, sGTM webhook replays, or SDK bugs create duplicate conversions with double-counted revenue.

### 5. Reattribution race condition

`Conversions::ReattributionService#run` (line 16) does delete + recalculate in a transaction but without any lock. Two concurrent `ReattributionJob` runs for the same conversion can produce duplicate or zero credits.

### Data Flow (Current)

```
SDK → POST /conversions → TrackingService.new.call
  → normalized_revenue: zero? → nil (BUG)
  → Conversion.create!  (no dedup)
  → success_result

SDK → POST /identify → IdentificationService.new.call
  → identity.traits = traits  (full overwrite, BUG)

SDK → POST /events → EventsController → IngestionService.call
  → billing blocked? → 202 {billing_blocked: true}  (silent, BUG)

ReattributionJob → ReattributionService.new.call
  → delete_existing_credits + calculate_new_credits  (no lock, BUG)
```

---

## Proposed Solution

### 1. Preserve revenue=0

- Remove `revenue.to_f.zero?` guard from `normalized_revenue`
- Change validation from `greater_than: 0` to `greater_than_or_equal_to: 0`
- Add negative-revenue guard (`revenue.to_f.negative?` → nil)

### 2. Deep merge traits

- Replace `identity.traits = traits` with `identity.traits = (identity.traits || {}).deep_merge(traits)`

### 3. Return HTTP 402 for billing block

- Check `can_ingest_events?` in `EventsController` before calling ingestion service
- Return 402 Payment Required with `{ error: "Account cannot accept events", billing_blocked: true }`

### 4. Idempotency key for conversions

- Add `idempotency_key` column (nullable string, unique per account via partial index)
- Service checks for existing conversion with same key before creating
- Controller permits param, returns 200 (not 201) with `duplicate: true` for deduped conversions

### 5. Advisory lock on reattribution

- Wrap delete+recalculate in `pg_advisory_xact_lock` keyed on conversion ID
- Follows `Sessions::CreationService#with_session_lock` pattern

### Data Flow (Proposed)

```
SDK → POST /conversions {idempotency_key: "abc"}
  → TrackingService: check idempotency_key → existing? return it : create
  → normalized_revenue: nil? → nil, negative? → nil, else → keep (0 OK)
  → success_result(duplicate: maybe)

SDK → POST /identify {traits: {new: "val"}}
  → IdentificationService: deep_merge(existing_traits, new_traits)

SDK → POST /events
  → EventsController: can_ingest? → no? → 402
  → yes? → IngestionService.call (existing flow)

ReattributionJob → ReattributionService
  → pg_advisory_xact_lock(conversion.id)
  → delete + recalculate (serialized)
```

### Key Files

| File | Changes |
|------|---------|
| `app/services/conversions/tracking_service.rb` | Fix revenue normalization, add idempotency check |
| `app/models/concerns/conversion/validations.rb` | `>= 0` instead of `> 0` |
| `app/services/identities/identification_service.rb` | `deep_merge` traits |
| `app/controllers/api/v1/events_controller.rb` | Billing check → 402 |
| `app/controllers/api/v1/conversions_controller.rb` | Permit `idempotency_key`, 200 for dupes |
| `app/services/conversions/response_builder.rb` | Add `duplicate` flag |
| `app/services/conversions/reattribution_service.rb` | Advisory lock |
| New migration | `add_idempotency_key_to_conversions` |

---

## All States

| # | State | Condition | Expected Behavior |
|---|-------|-----------|-------------------|
| 1a | Revenue = 0 | `revenue: 0` | Stored as `0.00` |
| 1b | Revenue = nil | `revenue: nil` | Stored as nil |
| 1c | Revenue = -1 | `revenue: -1` | Normalized to nil |
| 1d | Revenue = 99.99 | `revenue: 99.99` | Stored as `99.99` |
| 2a | First identify | No prior traits | Traits stored as-is |
| 2b | New keys | Existing `{a:1}`, new `{b:2}` | Merged: `{a:1, b:2}` |
| 2c | Overlapping keys | Existing `{a:1}`, new `{a:2}` | Updated: `{a:2}` |
| 2d | Empty traits | Existing `{a:1}`, new `{}` | Unchanged: `{a:1}` |
| 2e | Nested merge | Existing `{addr:{city:"NY"}}`, new `{addr:{zip:"10001"}}` | Deep merged |
| 3a | Billing OK | `can_ingest_events? == true` | 202 (normal flow) |
| 3b | Billing blocked | `can_ingest_events? == false` | 402 Payment Required |
| 4a | No key | `idempotency_key: nil` | Normal create, 201 |
| 4b | New key | `idempotency_key: "abc"` | Create, 201 |
| 4c | Duplicate key | Same account + key exists | Return existing, 200 |
| 4d | Same key, diff account | Different account | Create, 201 |
| 5a | Single reattribution | One job | Normal credits |
| 5b | Concurrent reattribution | Two jobs, same conversion | Serialized, no duplicates |

---

## Implementation Tasks

### Phase 1: Revenue + Traits (Low Complexity)

- [x] **1.1** Fix `normalized_revenue` in `TrackingService`
- [x] **1.2** Fix validation in `Conversion::Validations`
- [x] **1.3** Update unit tests for revenue=0
- [x] **1.4** Fix `persist_identity` in `IdentificationService`
- [x] **1.5** Add unit tests for trait merge

### Phase 2: Billing Block (Medium Complexity)

- [x] **2.1** Add billing check + 402 in `EventsController`
- [x] **2.2** Add controller test for 402 response

### Phase 3: Idempotency (High Complexity)

- [x] **3.1** Create migration for `idempotency_key`
- [x] **3.2** Update `TrackingService` for idempotency check
- [x] **3.3** Update `ConversionsController` to permit param + 200 for dupes
- [x] **3.4** Update `ResponseBuilder` with duplicate flag
- [x] **3.5** Add unit tests for idempotency

### Phase 4: Reattribution Lock

- [x] **4.1** Add advisory lock to `ReattributionService`
- [x] **4.2** Add reattribution idempotency test

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Revenue 0 persists | `test/services/conversions/tracking_service_test.rb` | `revenue: 0` stored as 0 |
| Revenue -1 normalized | `test/services/conversions/tracking_service_test.rb` | Negative → nil |
| Traits merge | `test/services/identities/identification_service_test.rb` | Existing traits preserved |
| Nested traits merge | `test/services/identities/identification_service_test.rb` | Deep merge works |
| Billing 402 | `test/controllers/api/v1/events_controller_test.rb` | HTTP 402 when blocked |
| Idempotency dedup | `test/services/conversions/tracking_service_test.rb` | Same key → existing record |
| Idempotency scoped | `test/services/conversions/tracking_service_test.rb` | Different account → new record |
| Reattribution lock | `test/services/conversions/reattribution_service_test.rb` | No duplicate credits |

---

## Definition of Done

- [x] All 5 fixes implemented
- [x] Unit tests pass (`bin/rails test`)
- [x] No regressions
- [x] Spec updated with final state

---

## Out of Scope

- SDK-side idempotency key generation (next SDK version)
- Retroactive dedup of existing duplicate conversions
- Rate limiting (disabled for MVP per BaseController)
- E2E tests for billing block (requires Stripe test mode)
