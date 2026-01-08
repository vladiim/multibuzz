# Visitor & Session Tracking Specification v3

## Overview

This specification defines the visitor/session identification architecture for mbuzz, addressing:
- Duplicate visitors from concurrent requests (Turbo/Hotwire)
- Session timeout behavior (sliding vs fixed windows)
- Cross-device identity resolution
- SDK simplification

**Last Updated**: 2026-01-09
**Status**: ✅ ALL PHASES COMPLETE - Production ready

---

## Related Documents

| Document | Status | Relationship |
|----------|--------|--------------|
| `lib/docs/sdk/api_contract.md` | Active | Defines API contract - needs update for `identifier` |
| `mbuzz-ruby/lib/specs/v0.7.0_deterministic_sessions.md` | **SUPERSEDED** | Time-bucket approach replaced by server-side |
| `lib/specs/old/server_side_session_resolution.md` | Archived | Merged into this spec |
| `lib/specs/old/turbo_session_deduplication_spec.md` | Archived | Merged into this spec |

### Document Conflicts Resolved

| Topic | Previous Direction | New Direction |
|-------|-------------------|---------------|
| Session ID generation | v0.7.0: SDK time-buckets | Server-side only, remove from SDK |
| Session cookie | v0.7.0: Keep `_mbuzz_sid` | Remove - server resolves sessions |
| Visitor deduplication | Not addressed | Add fingerprint-based canonical lookup |
| `identifier` param | Not addressed | Add to all API calls |

---

## Problem Statement

### The Duplicate Visitor Problem

When a page with Turbo frames loads, multiple HTTP requests arrive simultaneously before cookies are set:

| ID Type | Current Generation | Concurrent Request Behavior |
|---------|-------------------|----------------------------|
| Session ID | Deterministic (fingerprint + time-bucket) | SAME session_id ✓ |
| Visitor ID | Random (`SecureRandom.hex(32)`) | DIFFERENT visitor_id ✗ |

**Root Cause**: `Visitors::LookupService` creates visitors without any deduplication logic.

**Evidence** (production UAT account):
- 144,305 visitors / 2 device fingerprints = 72,154x inflation

### The Time-Bucket Problem

SDK uses fixed 30-minute time buckets:
```
Bucket 0: 10:00:00 - 10:29:59
Bucket 1: 10:30:00 - 10:59:59
```

User active at 10:28 → 10:32 (4 min gap) gets **NEW** session because they crossed the bucket boundary.

Industry standard (GA4, Mixpanel, Amplitude): True sliding window - activity within 30 min extends session.

---

## Current State Analysis

### What's Already Implemented ✓

| Component | File | Line | Verified |
|-----------|------|------|----------|
| Server-side session resolution | `sessions/resolution_service.rb` | 28-35 | ✓ Uses `last_activity_at > 30.min.ago` |
| Session activity tracking | `sessions/tracking_service.rb` | 32 | ✓ `session.update!(last_activity_at: Time.current)` |
| Device fingerprint storage | `db/schema.rb` | 337 | ✓ `sessions.device_fingerprint` column |
| Session resolution index | `db/schema.rb` | 348 | ✓ `index_sessions_for_resolution` |
| Events call resolution service | `events/processing_service.rb` | 44-50 | ✓ Calls `Sessions::ResolutionService` |
| SDK accepts ip/user_agent | `mbuzz-ruby/lib/mbuzz/client.rb` | 10 | ✓ `track(ip:, user_agent:)` |
| API contract documents server-side | `lib/docs/sdk/api_contract.md` | 187-191 | ✓ "preferred method" |

### What's Missing ✗

| Component | Current Code | Gap | Required Change |
|-----------|--------------|-----|-----------------|
| Visitor deduplication | `visitors/lookup_service.rb:16-20` - plain `create()` | No fingerprint check | Add canonical visitor lookup before create |
| Cross-device identity | `sessions/resolution_service.rb` - visitor-only | No identity lookup | Add identity.visitors cross-check |
| Conversions fingerprint | `conversions/tracking_service.rb:67-75` - visitor_id only | No fallback | Add fingerprint-based visitor lookup |
| `identifier` param | Not in any SDK or controller | New feature | Add to events/conversions controllers |
| SDK session removal | `mbuzz-ruby/middleware/tracking.rb:158-163` - sets cookie | SDK manages session | Remove session cookie, simplify middleware |

---

## Requirements

### R1: Visitor Deduplication

**When**: Creating a new visitor (no existing visitor_id match)
**Do**: Check for canonical visitor via recent session with same fingerprint
**File**: `app/services/visitors/lookup_service.rb`

```
IF visitor_id exists in DB → use it
ELSE IF recent session (30 sec) exists with same fingerprint → use that visitor
ELSE → create new visitor
```

### R2: Identity-Based Session Resolution

**When**: `identifier` param provided (e.g., `{ email: 'user@example.com' }`)
**Do**: Find active session across ALL visitors linked to that identity
**File**: `app/services/sessions/resolution_service.rb`

```
1. Find identity by external_id
2. Get all identity.visitors
3. Find active session for ANY of those visitors + current fingerprint
4. If found, link current visitor to identity
```

### R3: Conversions Fingerprint Fallback

**When**: visitor_id not found
**Do**: Fall back to fingerprint-based visitor lookup
**File**: `app/services/conversions/tracking_service.rb`

```
IF event provided → use event.visitor
ELSE IF visitor_id found → use it
ELSE IF fingerprint matches recent session → use that visitor
ELSE → error (no visitor found)
```

### R4: SDK Simplification

**Remove from SDKs**:
- Session cookie (`_mbuzz_sid`)
- Session ID generation logic
- Time-bucket calculations

**Keep**:
- Visitor cookie (`_mbuzz_vid`) - 2 year expiry

**Add to all API calls**:
- `ip` - client IP address
- `user_agent` - client User-Agent string
- `identifier` - optional, any key/value for identity resolution

### R5: Backwards Compatibility

Old SDK versions (without ip/user_agent):
- Continue to work with visitor_id-only lookup
- No fingerprint-based deduplication
- Documented as deprecated behavior

---

## Data Model

### Current Schema (Validated)

```
Identity
  - external_id: string (e.g., "user_123" or "email@example.com")
  - traits: jsonb
  - has_many :visitors

Visitor
  - visitor_id: string (64 char hex)
  - identity_id: optional FK
  - has_many :sessions

Session
  - session_id: string (64 char hex)
  - visitor_id: FK
  - device_fingerprint: string (32 char hex)
  - last_activity_at: datetime
  - started_at: datetime
  - ended_at: datetime
```

### Identifier Format

The `identifier` param is flexible - any key/value:
```ruby
identifier: { email: 'user@example.com' }
identifier: { user_id: '12345' }
identifier: { customer_id: 'cust_abc' }
```

Stored as `Identity.external_id` = the VALUE (not key:value format).
The KEY is implicit based on usage.

---

## Resolution Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                    Session Resolution                        │
├─────────────────────────────────────────────────────────────┤
│ 1. EXISTING SESSION                                         │
│    visitor + fingerprint + last_activity < 30min            │
│    → Return session, update last_activity_at                │
├─────────────────────────────────────────────────────────────┤
│ 2. IDENTITY CROSS-DEVICE (if identifier provided)           │
│    Find Identity → Get all identity.visitors                │
│    → Check for active session on ANY linked visitor         │
│    → Link current visitor to identity                       │
├─────────────────────────────────────────────────────────────┤
│ 3. CREATE NEW SESSION                                       │
│    → New session with current visitor + fingerprint         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Visitor Resolution                        │
├─────────────────────────────────────────────────────────────┤
│ 1. EXISTING VISITOR                                         │
│    visitor_id found in DB → use it                          │
├─────────────────────────────────────────────────────────────┤
│ 2. CANONICAL VISITOR (fingerprint)                          │
│    Recent session (30 sec) with same fingerprint            │
│    → Use that session's visitor                             │
├─────────────────────────────────────────────────────────────┤
│ 3. CREATE NEW VISITOR                                       │
│    → New visitor record                                     │
└─────────────────────────────────────────────────────────────┘
```

---

## Industry Comparison

| Feature | GA4 | Mixpanel | Amplitude | Mbuzz (Proposed) |
|---------|-----|----------|-----------|------------------|
| Session timeout | 30min sliding | 30min sliding | 30min web | 30min sliding ✓ |
| Anonymous ID | Cookie-based | Random UUID | Random device_id | Cookie + fingerprint |
| Identity merge | Manual | Auto (Simple ID) | Auto | Manual via identify() |
| Cross-device | User-ID feature | Identity clusters | Amplitude ID | Identity.visitors |

Sources:
- [GA4 Sessions](https://support.google.com/analytics/answer/12798876)
- [Mixpanel Sessions](https://docs.mixpanel.com/docs/features/sessions)
- [Amplitude Identity](https://amplitude.com/docs/get-started/identify-users)

---

## Implementation Checklist

### Phase 0: Critical Fixes (BLOCKING) ✅ COMPLETE

**These bugs were found during validation review and have been fixed.**

- [x] **BUG-001**: Wire `device_fingerprint` from `ProcessingService` to `LookupService`
  - File: `app/services/events/processing_service.rb:21-27`
  - Fix: Added `device_fingerprint: device_fingerprint` to LookupService call
  - Commit: `fix(events): pass device fingerprint to visitor lookup for deduplication`

- [x] **BUG-002**: Standardize fingerprint calculation (use raw IP everywhere)
  - File: `app/services/conversions/tracking_service.rb:100-101`
  - Fix: Changed from anonymized IP to raw IP (matching ResolutionService)
  - Commit: `fix(conversions): use raw IP for fingerprint matching sessions`

- [x] **TEST-001**: Add integration test for concurrent event requests
  - File: `test/integration/concurrent_events_dedup_test.rb`
  - Proves visitor deduplication works via events endpoint

- [x] **TEST-002**: Add unit test verifying fingerprint passed to LookupService
  - File: `test/services/events/processing_service_test.rb:181-206`

### Phase 1: Visitor Deduplication (API) ✅ COMPLETE

- [x] Update `Visitors::LookupService` with fingerprint-based canonical lookup
- [x] Add `session_id` and `device_fingerprint` optional params
- [x] Write tests for concurrent request scenarios
- [x] BUG-001 fixed - fingerprint now passed to LookupService

### Phase 2: Identity Cross-Device (API)

- [x] Update `Sessions::ResolutionService` with identity lookup
- [x] Add `identifier` param to events/conversions controllers
- [x] Link visitors to identity on first match
- [x] Write cross-device test scenarios

### Phase 3: Conversions Fallback (API) ✅ COMPLETE

- [x] Update `Conversions::TrackingService` with fingerprint fallback
- [x] Add `ip` and `user_agent` params
- [x] Write tests for visitor resolution chain
- [x] BUG-002 fixed - fingerprint now uses raw IP (matches sessions)

### Phase 4: SDK Simplification ✅ COMPLETE

- [x] mbuzz-ruby: Remove session cookie and ID generation
- [x] mbuzz-ruby: Add ip/user_agent/identifier to all calls
- [x] mbuzz-node: Same changes (v0.7.0 published to npm)
- [x] mbuzz-python: Same changes (v0.7.0 published to PyPI)
- [x] mbuzz-php: Same changes (v0.7.0 published to Packagist)
- [x] Update SDK documentation (READMEs updated)

---

## Implementation Validation Review (2026-01-09)

### Summary

A deep-dive validation review was conducted comparing the spec requirements against actual implementation. **Two critical bugs were found that prevent core features from working.**

### Bug Analysis

#### BUG-001: Visitor Deduplication Not Wired Up (CRITICAL)

**Code Location:** `app/services/events/processing_service.rb` lines 21-22

**Current Code:**
```ruby
def visitor_result
  @visitor_result ||= Visitors::LookupService.new(account, event_data["visitor_id"], is_test: is_test).call
end
```

**Problem:** The `device_fingerprint` is calculated at line 74-78 but **never passed** to `LookupService`. The `LookupService` has the canonical visitor lookup logic (lines 33-36) but it receives `nil` for fingerprint, so deduplication never triggers.

**Result:** The primary feature (R1: Visitor Deduplication) is **not working**. Concurrent Turbo requests will continue creating duplicate visitors.

**Fix Required:**
```ruby
def visitor_result
  @visitor_result ||= Visitors::LookupService.new(
    account,
    event_data["visitor_id"],
    is_test: is_test,
    device_fingerprint: device_fingerprint  # ADD THIS
  ).call
end
```

#### BUG-002: Fingerprint Calculation Mismatch (CRITICAL)

**Code Locations:**
- `app/services/sessions/resolution_service.rb` line 88-89: Uses **raw IP**
- `app/services/events/processing_service.rb` line 74-78: Uses **raw IP**
- `app/services/conversions/tracking_service.rb` lines 100-108: Uses **anonymized IP**

**Problem:** When conversion fingerprint fallback tries to find a visitor:
1. It calculates fingerprint using anonymized IP: `192.168.1.0`
2. It searches sessions which store fingerprint with raw IP: `192.168.1.42`
3. **They will never match**

**Result:** Conversion fingerprint fallback (R3) is **broken**. Will silently fail.

**Fix Required:** Change `Conversions::TrackingService` to use raw IP:
```ruby
def device_fingerprint
  @device_fingerprint ||= Digest::SHA256.hexdigest("#{ip}|#{user_agent}")[0, FINGERPRINT_LENGTH]
end

# Remove anonymized_ip method - not needed for fingerprint
```

### What's Working

| Feature | Status | Notes |
|---------|--------|-------|
| Server-side session resolution | ✅ WORKING | 30-min sliding window |
| Session continuation | ✅ WORKING | `last_activity_at` updated |
| Identity cross-device lookup | ✅ WORKING | Finds sessions across visitors |
| Visitor-to-identity linking | ✅ WORKING | First match links |
| SDK simplification (Ruby) | ✅ WORKING | Session cookie removed |
| Backwards compatibility | ✅ WORKING | Works without ip/user_agent |

### What's NOT Working

| Feature | Status | Root Cause |
|---------|--------|------------|
| Visitor deduplication | ❌ BROKEN | BUG-001: Fingerprint not passed |
| Conversion fingerprint fallback | ❌ BROKEN | BUG-002: IP format mismatch |

### Test Coverage Gaps

| Missing Test | Priority |
|--------------|----------|
| Concurrent event requests deduplicate visitors | HIGH |
| Fingerprint passed from ProcessingService to LookupService | HIGH |
| Fingerprint consistency between event and conversion | MEDIUM |
| IPv6 handling | LOW |

### Production Readiness

**Status: ❌ NOT READY**

Both critical bugs cause silent failures - no errors, just incorrect behavior. The duplicate visitor problem (the primary issue we're trying to solve) will persist until BUG-001 is fixed.

---

## Development Workflow

### Task Flow (Per Feature)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FEATURE DEVELOPMENT CYCLE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  1. INTEGRATION TEST (RED)                                                  │
│     └─ Write failing test in sdk_integration_tests/                         │
│     └─ Test against Ruby SDK + API first                                    │
│                                                                              │
│  2. UNIT TESTS (RED)                                                        │
│     └─ API: test/services/*_test.rb                                         │
│     └─ SDK: mbuzz-ruby/test/*_test.rb                                       │
│                                                                              │
│  3. IMPLEMENTATION                                                          │
│     └─ API: app/services/*.rb                                               │
│     └─ SDK: mbuzz-ruby/lib/mbuzz/*.rb                                       │
│                                                                              │
│  4. UNIT TESTS (GREEN)                                                      │
│     └─ bin/rails test (API)                                                 │
│     └─ bundle exec rake test (SDK)                                          │
│                                                                              │
│  5. INTEGRATION TEST (GREEN)                                                │
│     └─ Run sdk_integration_tests against local                              │
│                                                                              │
│  6. UPDATE SPEC                                                             │
│     └─ Mark checkbox complete in this spec                                  │
│     └─ Add any learnings/changes                                            │
│                                                                              │
│  7. GIT COMMIT                                                              │
│     └─ Commit with date: yesterday 8pm-12am Sydney time (random)            │
│     └─ Format: feat(scope): description                                     │
│                                                                              │
│  8. NEXT FEATURE                                                            │
│     └─ Repeat steps 1-7                                                     │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### SDK Rollout Order

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SDK ROLLOUT ORDER                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PHASE A: RUBY (Primary)                                                    │
│  ─────────────────────────                                                  │
│  1. Complete ALL features for mbuzz-ruby                                    │
│  2. All integration tests passing                                           │
│  3. Deploy API changes to production                                        │
│  4. Release mbuzz-ruby gem (v0.7.0)                                         │
│  5. Update pet_resorts UAT app                                              │
│  6. Verify in production                                                    │
│                                                                              │
│  PHASE B: NODE                                                              │
│  ─────────────────────────                                                  │
│  1. Port changes to mbuzz-node                                              │
│  2. Run sdk_integration_tests for Node                                      │
│  3. Release npm package                                                     │
│                                                                              │
│  PHASE C: PYTHON                                                            │
│  ─────────────────────────                                                  │
│  1. Port changes to mbuzz-python                                            │
│  2. Run sdk_integration_tests for Python                                    │
│  3. Release pip package                                                     │
│                                                                              │
│  PHASE D: PHP                                                               │
│  ─────────────────────────                                                  │
│  1. Port changes to mbuzz-php                                               │
│  2. Run sdk_integration_tests for PHP                                       │
│  3. Release composer package                                                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Commit Time Convention

All commits use **yesterday's date** between **8pm-12am Sydney time** (AEDT/AEST):

```bash
# Generate random time between 20:00-23:59 Sydney yesterday
GIT_AUTHOR_DATE="$(TZ='Australia/Sydney' date -v-1d +%Y-%m-%d)T$(printf '%02d:%02d:%02d' $((20 + RANDOM % 4)) $((RANDOM % 60)) $((RANDOM % 60)))+11:00"
GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
git commit -m "feat(sessions): add server-side resolution"
```

---

### Phase 5: Documentation ✅ COMPLETE

**Files updated:**

| File | Change |
|------|--------|
| `lib/docs/sdk/api_contract.md` | Added `identifier` param, updated session resolution docs |
| `mbuzz-ruby/lib/specs/v0.7.0_deterministic_sessions.md` | Marked as SUPERSEDED |
| `mbuzz-ruby/README.md` | Session handling updated |
| `mbuzz-node/README.md` | Session handling updated |
| `mbuzz-python/README.md` | Minimal, no changes needed |
| `mbuzz-php/README.md` | Session handling updated |
| `app/views/docs/_getting_started.html.erb` | Updated to server-side session resolution |
| `app/views/docs/_platforms_shopify.html.erb` | Removed session cookie references |

**Checklist:**
- [x] Update `api_contract.md` with `identifier` param
- [x] Mark v0.7.0 spec as superseded
- [x] Update SDK READMEs
- [x] Update getting started guide
- [x] Update Shopify docs

---

## Testing Scenarios

| Scenario | Expected Behavior |
|----------|-------------------|
| Concurrent Turbo requests (same fingerprint) | Single visitor created |
| User returns after 29 min | Same session extended |
| User returns after 31 min | New session created |
| Same email on different devices | Sessions linked via identity |
| Old SDK without ip/user_agent | Works, no deduplication |

---

## Monitoring

### Key Metrics

| Metric | Expected | Alert If |
|--------|----------|----------|
| Visitors per session | ~1.0 | < 0.5 or > 2.0 |
| Canonical visitor hit rate | > 0% in Turbo apps | Always 0% |
| Session continuation rate | > 50% | < 20% |

### Validation Query

```sql
SELECT
  DATE(created_at) as date,
  COUNT(DISTINCT visitor_id) as visitors,
  COUNT(DISTINCT session_id) as sessions,
  COUNT(DISTINCT visitor_id)::float / NULLIF(COUNT(DISTINCT session_id), 0) as ratio
FROM events
WHERE account_id = ?
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY 1
ORDER BY 1;
```

---

## Rollback Plan

1. **If visitor deduplication causes issues**: Remove canonical lookup from `LookupService`, duplicates resume but no data loss
2. **If SDK changes break**: Revert SDK, API continues to work with old format
3. **All changes are additive** - no destructive migrations

---

## Progress Log

| Date | Item | Status |
|------|------|--------|
| 2026-01-08 | Spec v3 - validated against codebases | Complete |
| 2026-01-09 | Phase 1: Visitor Deduplication | Complete (code written) |
| 2026-01-09 | Phase 2: Identity Cross-Device | Complete |
| 2026-01-09 | Phase 3: Conversions Fallback | Complete (code written) |
| 2026-01-09 | Phase 4: SDK Simplification (mbuzz-ruby) | Complete |
| 2026-01-09 | **Validation Review - CRITICAL BUGS FOUND** | BUG-001, BUG-002 |
| 2026-01-09 | Phase 0: Critical Fixes | **COMPLETE** |
| 2026-01-09 | Phase 4: SDK Simplification (all SDKs) | **COMPLETE** |
| 2026-01-09 | Phase 5: Documentation | **COMPLETE** |

### Phase 0 Fix Details (2026-01-09)

**BUG-001 Fixed**: `fix(events): pass device fingerprint to visitor lookup for deduplication`
- ProcessingService now passes `device_fingerprint` to LookupService
- Integration test added: `test/integration/concurrent_events_dedup_test.rb`
- Unit test added: `test/services/events/processing_service_test.rb:181-206`

**BUG-002 Fixed**: `fix(conversions): use raw IP for fingerprint matching sessions`
- TrackingService now uses raw IP for fingerprint (matching ResolutionService)
- Test added: `test/services/conversions/tracking_service_test.rb:530-557`
