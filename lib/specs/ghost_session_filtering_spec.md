# Ghost Session Filtering Specification

**Date:** 2026-02-13
**Priority:** P0
**Status:** Draft
**Branch:** `feature/ghost-session-filtering`

---

## Summary

Ghost sessions (bot traffic, asset requests that bypass SDK navigation detection) inflate visitor counts by 464% compared to GA4 and pollute attribution models with phantom touchpoints. The `suspect` flag already exists on sessions but is never used for filtering. This spec adds suspect filtering at three layers: dashboard display, attribution journey building, and retroactive cleanup of existing poisoned data.

---

## Current State

### Evidence

Production data (PetPro360 account, 2026-02-12):

| Metric | GA4 | Multibuzz | Inflation |
|--------|-----|-----------|-----------|
| Total visitors | 2,430 | 13,702 | 464% |
| Non-direct channels | ~2,430 | ~2,758 | ~13% (healthy) |
| Direct channel only | — | 10,944 | Almost entirely ghost |

Ghost session rate: **64.2%** (critical threshold: 50%). 98.7% of sessions have zero events. The non-direct channels roughly match GA4, confirming that the `suspect` flag correctly identifies the noise — it's just never filtered.

### How Ghost Sessions Enter the System

1. **Bot traffic** — Requests without `Sec-Fetch-*` headers hit the SDK blacklist fallback (`framework_sub_request?`). If the request isn't Turbo, HTMX, Unpoly, or XHR, a session is created.
2. **Asset/prefetch requests** — Browsers and CDNs making preflight or resource requests that don't match any blacklist pattern.
3. **Concurrent burst race conditions** — IP rotation across rapid-fire requests creates multiple fingerprints for the same logical visitor, bypassing the advisory lock.

### The `suspect` Flag (Already Exists)

`Sessions::CreationService` (line 237) marks sessions as `suspect: true` at creation:

```ruby
def suspect_session?
  referrer.blank? &&
    normalized_utm.values.none?(&:present?) &&
    click_ids.empty?
end
```

This correctly identifies ghost traffic: no referrer, no UTMs, no click IDs. The flag is set and stored — but never read.

### Data Flow (Current)

```
Session created → suspect: true/false stored → IGNORED everywhere

Dashboard:
  SessionsScope.base_scope → account.sessions.production (no suspect filter)
    → FunnelStagesQuery: sessions_scope.distinct.count(:visitor_id) → 13,702 (inflated)
    → TotalsQuery: reads journey_session_ids (contains ghost session IDs)
    → TimeSeriesQuery: counts all sessions (includes ghosts)

Attribution:
  JourneyBuilder.sessions_in_window → all visitor sessions (includes suspects)
    → Calculator → AttributionCredit records → journey_session_ids on conversion
    → Ghost sessions baked into journey_session_ids permanently
    → All downstream queries read poisoned journey data
```

### Pollution Depth

The ghost session pollution is **3 layers deep**:

| Layer | File | What's Poisoned |
|-------|------|-----------------|
| **1. Dashboard counts** | `Dashboard::Scopes::SessionsScope` (line 21) | Visitor counts, session counts, channel breakdowns |
| **2. Journey building** | `Attribution::JourneyBuilder` (line 22) | Ghost sessions become touchpoints in conversion journeys |
| **3. Attribution credits** | `Conversions::AttributionCalculationService` (line 82) | Ghost session IDs baked into `journey_session_ids`, credits created for phantom touchpoints |

Fixing layer 1 alone hides ghosts from the dashboard but leaves attribution poisoned. Fixing layers 1+2 stops future poisoning but leaves existing conversions with dirty journey data.

---

## Proposed Solution

Add `where(suspect: false)` at the two entry points where session data feeds into display and attribution. Add a model scope for clean API. Retroactively repair existing poisoned conversions.

### Data Flow (Proposed)

```
Session created → suspect: true/false stored

Dashboard:
  SessionsScope.base_scope → account.sessions.production.qualified (suspect: false)
    → FunnelStagesQuery: ~2,758 visitors (matches GA4)
    → All dashboard queries automatically filtered

Attribution:
  JourneyBuilder.sessions_in_window → .where(suspect: false)
    → Only real touchpoints in journey
    → Clean AttributionCredit records
    → Clean journey_session_ids

Retroactive:
  CleanupService → find conversions with suspect session IDs in journey
    → Remove ghost IDs from journey_session_ids
    → Delete ghost-linked AttributionCredit records
    → Re-run attribution for affected conversions
```

### Key Files

| File | Changes |
|------|---------|
| `app/models/concerns/session/scopes.rb` | Add `qualified` scope: `where(suspect: false)` |
| `app/services/dashboard/scopes/sessions_scope.rb` | Chain `.qualified` in `base_scope` |
| `app/services/attribution/journey_builder.rb` | Add `.where(suspect: false)` to `sessions_in_window` |
| `app/services/attribution/cross_device_journey_builder.rb` | Add `.where(suspect: false)` to `sessions_in_window` |
| `app/services/data_integrity/checks/ghost_session_rate.rb` | Align ghost definition with `suspect` flag |
| `app/services/data_integrity/checks/session_inflation.rb` | Measure inflation on qualified sessions only |
| New: `app/services/data_integrity/ghost_session_cleanup_service.rb` | Retroactive journey repair |
| New migration | Add index on `sessions.suspect` for query performance |

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Filter at scope level vs. query level | Scope (`Session.qualified`) | Single source of truth, impossible to forget |
| Delete ghost sessions vs. filter them | Filter only | Preserve audit trail, support future bot analytics |
| Scope name | `qualified` | Marketing-native term ("qualified traffic"), reads naturally: `sessions.production.qualified` |
| Retroactive repair strategy | Re-run attribution per conversion | Journey session IDs are derived data — recalculate from clean source |
| Surveillance check alignment | Align ghost check with `suspect` flag | Currently ghost check uses its own heuristic that duplicates `suspect_session?` logic |

---

## All States

| # | State | Condition | Expected Behavior |
|---|-------|-----------|-------------------|
| 1a | Suspect session | `suspect: true`, no events | Excluded from dashboard, excluded from journeys |
| 1b | Suspect session with events | `suspect: true`, has events | Excluded from dashboard, excluded from journeys (conservative — if it's suspect, filter it regardless of events) |
| 1c | Real session, direct | `suspect: false`, direct channel | Included in dashboard, included in journeys |
| 1d | Real session, attributed | `suspect: false`, has UTMs/referrer | Included in dashboard, included in journeys |
| 2a | Conversion with clean journey | No suspect sessions in `journey_session_ids` | No change needed |
| 2b | Conversion with mixed journey | Some suspect, some real in `journey_session_ids` | Remove suspect IDs, keep real, re-run attribution |
| 2c | Conversion with all-ghost journey | Only suspect sessions in `journey_session_ids` | Clear `journey_session_ids`, delete credits, conversion attributed to converting session only |
| 3a | New conversion after fix | Future conversion | JourneyBuilder produces clean journey automatically |
| 3b | Dashboard after fix | Visitor count query | Should approximate GA4 numbers (~2,400-2,800 range) |
| 4a | Test mode sessions | `is_test: true` | Unaffected — test mode already has separate scope |
| 4b | Surveillance checks | Ghost rate check | Should use `suspect` flag directly, thresholds recalibrated |

---

## Implementation Tasks

### Phase 1: Prospective Filtering (Stop the Bleeding)

- [x] **1.1** Add `qualified` scope to `Session::Scopes`: `scope :qualified, -> { where(suspect: false) }`
- [x] **1.2** Chain `.qualified` in `Dashboard::Scopes::SessionsScope#base_scope`
- [x] **1.3** Add `.qualified` to `Attribution::JourneyBuilder#sessions_in_window`
- [x] **1.4** Add `.qualified` to `Attribution::CrossDeviceJourneyBuilder#sessions_in_window`
- [ ] **1.5** Add database index: `add_index :sessions, :suspect`
- [x] **1.6** Write unit tests for all 4 changes

### Phase 2: Surveillance Alignment

- [x] **2.1** Align `GhostSessionRate` check to use `suspect` flag instead of duplicating the heuristic
- [x] **2.2** Update `SessionInflation` check to measure qualified sessions only
- [ ] **2.3** Recalibrate thresholds (ghost rate warning: 30%, critical: 60% — suspect sessions are expected for direct traffic)
- [x] **2.4** Write unit tests for updated checks

### Phase 3: Retroactive Cleanup

- [x] **3.1** Build `DataIntegrity::GhostSessionCleanupService` to:
  - Find conversions where `journey_session_ids` contains suspect session IDs
  - Remove suspect session IDs from `journey_session_ids`
  - Delete `AttributionCredit` records linked to suspect sessions
  - Re-run `Conversions::AttributionCalculationService` for affected conversions
- [x] **3.2** Create rake task for one-time execution: `rake data_integrity:cleanup_ghost_journeys`
- [x] **3.3** Write unit tests for cleanup service
- [ ] **3.4** Run against production data, verify visitor count aligns with GA4 range

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| `qualified` scope excludes suspects | `test/models/session_test.rb` | `Session.qualified` returns only `suspect: false` |
| SessionsScope filters suspects | `test/services/dashboard/scopes/sessions_scope_test.rb` | Base scope chains `.qualified` |
| JourneyBuilder excludes suspects | `test/services/attribution/journey_builder_test.rb` | Suspect sessions not in touchpoints |
| CrossDeviceJourneyBuilder excludes suspects | `test/services/attribution/cross_device_journey_builder_test.rb` | Suspect sessions not in touchpoints |
| GhostSessionRate uses suspect flag | `test/services/data_integrity/checks/ghost_session_rate_test.rb` | Count matches `suspect: true` sessions |
| Cleanup removes ghost IDs | `test/services/data_integrity/ghost_session_cleanup_service_test.rb` | `journey_session_ids` cleaned |
| Cleanup re-runs attribution | `test/services/data_integrity/ghost_session_cleanup_service_test.rb` | Credits recalculated without ghosts |
| Cleanup handles all-ghost journey | `test/services/data_integrity/ghost_session_cleanup_service_test.rb` | Conversion attributed to converting session |

### Manual QA

1. Deploy Phase 1 to production
2. Run `DataIntegrity::CheckRunner` — ghost_session_rate should still report (ghosts exist, just filtered from display)
3. Check dashboard visitor count — should drop from ~13,700 to ~2,400-2,800 range
4. Create a test conversion — verify `journey_session_ids` contains no suspect sessions
5. Run Phase 3 cleanup rake task
6. Verify existing conversion journeys are repaired

---

## Definition of Done

- [ ] All phases implemented
- [ ] Unit tests pass (`bin/rails test`)
- [ ] Dashboard visitor count within 15% of GA4 equivalent
- [ ] No suspect session IDs in any `journey_session_ids` (post-cleanup)
- [ ] Surveillance checks aligned with `suspect` flag
- [ ] No regressions in attribution pipeline
- [ ] Spec updated with final state

---

## Out of Scope

- SDK-side bot detection improvements (Sec-Fetch blacklist tuning is a separate SDK version)
- Deleting ghost sessions from the database (preserved for audit trail and future bot analytics)
- Real-time bot scoring or ML-based detection (suspect heuristic is sufficient for now)
- Backfilling `suspect` flag on historical sessions that predate the flag (already set at creation time)
- Visitor deduplication across fingerprint rotation (separate concurrency issue)
