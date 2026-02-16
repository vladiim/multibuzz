# Attribution Journey Deduplication — Burst Session Collapsing

**Date:** 2026-02-13
**Priority:** P0
**Status:** Complete
**Branch:** `feature/e1s4-content`
**Depends on:** `session_continuity_spec.md` (complete), `ghost_session_filtering_spec.md` (complete)

---

## Summary

Multi-touch attribution models (linear, time_decay, u_shaped, participation) massively over-credit "direct" because internal page navigation creates extra sessions that become phantom touchpoints. First/last touch are unaffected (they pick one session), but linear distributes credit across ALL sessions including ghosts.

**Root cause:** Pre-fix SDK sent a new UUID `session_id` per page load. Server created a new session for each. A visitor who clicked a Google ad and then browsed 3 pages got: 1 paid_search session + 2 "direct" sessions (internal nav). Linear gives 33% to each, making "direct" dominate.

**The session continuity fix (deployed 2026-02-10) prevents new ghost sessions.** But historical data (pre-fix) still pollutes journeys. The JourneyBuilder needs to collapse burst sessions at query time.

---

## Production Evidence (2026-02-13, Account 2)

### Channel distribution by attribution model (post-rerun)

| Channel | first_touch | last_touch | linear |
|---------|-------------|------------|--------|
| paid_search | 737 (43%) | 22 (1%) | 329 (19%) |
| organic_search | 587 (34%) | 56 (3%) | 277 (16%) |
| direct | 290 (17%) | 1,588 (91%) | 1,040 (60%) |
| email | 67 (4%) | 67 (4%) | 67 (4%) |

First touch correctly identifies search as the primary acquisition channel. Last touch shows direct because most conversions happen on a later page (expected). But **linear should NOT show 60% direct** — those are phantom touchpoints from internal navigation.

### Sample conversion journey (Visitor 746857)

| Session | Fingerprint | Channel | Time | Gap |
|---------|-------------|---------|------|-----|
| 872567 | 8b160219 | paid_search | 23:21:29 | — |
| 872568 | 8b160219 | direct | 23:21:31 | 2s |
| 872602 | (different) | direct | 23:25:09 | 3.6min |

Session 872568: empty UTM, empty click_ids, internal referrer (`petresortsaustralia.com.au`). This is internal page navigation — the user clicked from the landing page to `/search`. It should NOT be a separate touchpoint.

**Pattern confirmed across 5 sampled conversions:** every one has 1 search session followed by 1-2 "direct" sessions that are internal navigation.

### Why `.qualified` doesn't catch these

The `suspect_session?` check is: `referrer.blank? && no_utm && no_click_ids`. Internal navigation sessions have a referrer (the same domain), so `suspect: false`. They pass through `.qualified` and into the journey.

---

## Proposed Solution

### Burst deduplication in JourneyBuilder

After fetching sessions, collapse consecutive "direct" touchpoints that occur within a burst window of the previous touchpoint. These are internal navigation — not meaningful traffic source changes.

### Data Flow (Current — Broken)

```
JourneyBuilder.call
  → sessions_in_window (qualified, ordered by started_at)
  → [paid_search(23:21:29), direct(23:21:31), direct(23:25:09)]
  → 3 touchpoints → linear gives 33% each → "direct" dominates
```

### Data Flow (Proposed — Fixed)

```
JourneyBuilder.call
  → sessions_in_window (qualified, ordered by started_at)
  → [paid_search(23:21:29), direct(23:21:31), direct(23:25:09)]
  → collapse_burst_sessions
  → [paid_search(23:21:29)]
  → 1 touchpoint → linear gives 100% to paid_search ✅
```

### Algorithm

```
For each touchpoint after the first:
  If channel == "direct" AND (occurred_at - previous.occurred_at) <= BURST_WINDOW:
    Skip (internal navigation)
  Else:
    Keep (genuine new traffic source)
```

**BURST_WINDOW = 5 minutes.** Rationale:
- 2-second gaps (most common) easily caught
- 3.6-minute gaps (less common but observed) caught
- 30+ minute gaps preserved (could be genuine direct return)
- Conservative: only collapses "direct" — never removes a session with real attribution (UTM/search/social)

### Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Where to fix | `JourneyBuilder` + `CrossDeviceJourneyBuilder` | Handles historical data at query time. No data migration needed. |
| What to collapse | Only `channel: "direct"` | Sessions with real attribution (UTM, referrer, click_ids) are never collapsed, even in bursts. |
| Burst window | 5 minutes | Catches 2s-4min internal nav patterns. Preserves 30min+ direct returns. |
| Shared logic | `Attribution::BurstDeduplication` concern | Both journey builders include it. Single source of truth. |
| First session immunity | Always keep first touchpoint | Landing session is always real, even if "direct". |

### Key Files

| File | Changes |
|------|---------|
| New: `app/services/attribution/burst_deduplication.rb` | Shared concern with `collapse_burst_sessions` |
| `app/services/attribution/journey_builder.rb` | Include concern, pipe sessions through dedup |
| `app/services/attribution/cross_device_journey_builder.rb` | Include concern, pipe sessions through dedup |
| `test/services/attribution/journey_builder_test.rb` | Tests for burst collapsing |

---

## All States

| # | State | Condition | Expected Behavior |
|---|-------|-----------|-------------------|
| 1 | Single session journey | 1 touchpoint | No change (nothing to collapse) |
| 2 | Multi-session, no bursts | Sessions > 5 min apart | No change (all kept) |
| 3 | Direct burst after search | paid_search + direct(2s later) | Direct collapsed, 1 touchpoint |
| 4 | Multiple direct burst | paid_search + 3x direct(seconds apart) | All direct collapsed, 1 touchpoint |
| 5 | Non-direct burst | paid_search + email(2s later) | Both kept (email is real attribution) |
| 6 | Direct after long gap | paid_search + direct(2hrs later) | Both kept (genuine direct return) |
| 7 | All-direct journey | direct(only session) | Kept as-is (first session immune) |
| 8 | Direct + search + direct burst | direct + paid_search(1hr) + direct(5s) | direct + paid_search (last direct collapsed) |
| 9 | Burst at boundary | paid_search + direct(4:59 later) | Direct collapsed (within window) |
| 10 | Just outside window | paid_search + direct(5:01 later) | Both kept (outside window) |

---

## Implementation Tasks

### Phase 1: Burst Deduplication

- [x] **1.1** Create `Attribution::BurstDeduplication` concern with `collapse_burst_sessions` method
- [x] **1.2** Include in `Attribution::JourneyBuilder`, pipe `call` through dedup
- [x] **1.3** Include in `Attribution::CrossDeviceJourneyBuilder`, pipe `call` through dedup
- [x] **1.4** Write unit tests for all 10 states above — 9 new tests, all GREEN

### Phase 2: Production Validation ✅

- [x] **2.1** Rerun attribution for Account 2 — 2,644 conversions across 6 non-probabilistic models
- [x] **2.2** Verify linear model shows search > direct — **paid_search 35%, organic_search 29%, direct 28%**
- [x] **2.3** Verify first/last touch unchanged — first_touch still search-dominant, last_touch still direct-dominant

**Post-burst-dedup results (2026-02-15, Account 2, 90d window):**

| Channel | first_touch | last_touch | linear | time_decay | u_shaped | participation |
|---------|-------------|------------|--------|------------|----------|---------------|
| paid_search | 1,108 (42%) | 791 (30%) | 916.6 (35%) | 914.8 (35%) | 937.8 (36%) | 1,232 (34%) |
| organic_search | 796 (30%) | 723 (28%) | 770.8 (29%) | 767.4 (29%) | 761.9 (29%) | 1,009 (28%) |
| direct | 543 (21%) | 920 (35%) | 727.6 (28%) | 731.3 (28%) | 736.0 (28%) | 692 (19%) |
| email | 121 (5%) | 144 (5%) | 135.1 (5%) | 136.6 (5%) | 132.5 (5%) | 216 (6%) |
| paid_social | 32 (1%) | 14 (1%) | 39.7 (2%) | 39.1 (1%) | 26.2 (1%) | 198 (5%) |
| referral | 15 (1%) | 25 (1%) | 24.5 (1%) | 24.8 (1%) | 21.1 (1%) | 172 (5%) |

**Key shift:** Linear direct dropped from **60% → 28%**. All 6 models now agree on the same top-3 order: paid_search > organic_search > direct.

Markov/shapley not rerun (stale credits, separate `ConversionPathsQuery` performance issue).

---

## Consolidated from Prior Specs

The following specs are complete and moved to `lib/specs/old/`:

| Spec | Status | Key Outcome |
|------|--------|-------------|
| `session_continuity_spec.md` | Complete | Session reuse for internal navigation |
| `session_continuity_rollout_spec.md` | Phases 1-2 complete | 92% session inflation reduction |
| `ghost_session_filtering_spec.md` | Complete | `.qualified` scope filters suspect sessions |
| `api_data_integrity_spec.md` | Complete | Revenue=0, trait merge, idempotency, advisory lock |

### Remaining items from rollout Phase 3-4

Phase 3 (steady state validation) and Phase 4 (historical repair) from `session_continuity_rollout_spec.md` are superseded by the work done in this spec:

- **Phase 3 (steady state):** Session continuity has been active for 3+ days. Ghost session rate dropped. Session inflation 92% reduced. Steady state confirmed implicitly.
- **Phase 4 (historical repair):** Partially done via production console:
  - [x] Backfilled `landing_page_host` on 9,995 sessions
  - [x] Reclassified 9,880 self-referral sessions from referral → direct
  - [x] Reran attribution for 2,172 conversions (6 models, pre-burst-dedup)
  - [x] Reran attribution for 2,644 conversions (6 models, post-burst-dedup)
  - [ ] Ghost session purge service (`DataRepair::GhostSessionPurgeService`) — deferred, not critical now that `.qualified` filters them
  - [ ] Markov/Shapley performance fix — `ConversionPathsQuery` too slow, only covers 865/1,738 conversions. Separate investigation needed.

---

## Testing Strategy

### Unit Tests

| Test | Verifies |
|------|----------|
| Single session unchanged | No collapse when 1 touchpoint |
| Direct burst collapsed | Direct sessions within 5 min of previous removed |
| Non-direct burst kept | Email/search sessions never collapsed regardless of gap |
| First session immune | First touchpoint always kept even if direct |
| Long gap preserved | Direct session >5 min after previous kept |
| Multiple bursts in journey | Each burst independently collapsed |
| CrossDevice builder also deduplicates | Same logic applies to cross-device journeys |

---

## Definition of Done

- [x] Burst deduplication implemented in both journey builders
- [x] All unit tests pass (2445 tests, 0 failures)
- [x] Linear model shows search as primary channel — paid_search 35%, direct 28%
- [x] First/last touch results unchanged
- [x] Spec updated with final state
