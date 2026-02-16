# Markov/Shapley Attribution Fix + Landing Page Host Backfill

**Date:** 2026-02-17
**Priority:** P0
**Status:** In Progress
**Branch:** `feature/e1s4-content`
**Depends on:** `attribution_accuracy_spec.md` (complete)

---

## Summary

Markov Chain and Shapley Value attribution models show **75.6% direct** while all 6 other models agree on **~28% direct**. Two code gaps prevent accurate probabilistic attribution:

1. `ConversionPathsQuery` feeds poisoned historical paths (no burst dedup, no `.qualified`) to the algorithms
2. `CrossDeviceCalculator` doesn't support probabilistic models — can't pass `conversion_paths`

Secondary issue: `landing_page_host` only populates on brand-new sessions (84% of qualified sessions missing it), limiting cross-domain self-referral detection.

---

## Production Evidence (2026-02-17, Account 2)

### Markov/Shapley vs other models (30d window)

| Channel | Markov Chain | Shapley Value | Linear | Time Decay | U Shaped |
|---------|-------------|---------------|--------|------------|----------|
| direct | **75.6%** | **75.6%** | 23.4% | 23.3% | 23.2% |
| paid_search | 13.3% | 13.2% | 35.4% | 35.5% | 36.1% |
| organic_search | 8.3% | 8.3% | 31.7% | 31.6% | 31.9% |

### ConversionPathsQuery diagnosis

```
Total conversion paths: 1,591
Paths containing "direct": 1,398 (87.9%)
Paths with consecutive direct (burst artifacts): 195 (12.3%)
Avg path length: 2.42
Sample: ["direct", "direct"], ["organic_search", "direct", "direct"]
```

87.9% of paths contain "direct" → direct gets a massive removal effect in Markov → 75.6% credit.

### landing_page_host coverage (last 7d)

| Segment | With host | Missing | Total |
|---------|-----------|---------|-------|
| Qualified | 5,945 | 31,837 | 37,782 |
| Suspect | 9,216 | 61,838 | 71,054 |

---

## Root Cause Analysis

### Problem 1: ConversionPathsQuery is poisoned

`Markov::ConversionPathsQuery#channel_path_for` loads sessions by raw `journey_session_ids`:

```ruby
def sessions_for(conversion)
  account.sessions.where(id: conversion.journey_session_ids)
end
```

Two things missing:
- **No `.qualified`** — suspect sessions leak into paths
- **No burst dedup** — consecutive direct sessions (internal nav artifacts) inflate direct's presence in paths from 28% → 87.9%

The Markov algorithm computes removal effects across ALL paths. When "direct" appears in 87.9% of paths, removing it collapses most paths → huge removal effect → 75.6% credit.

### Problem 2: CrossDeviceCalculator doesn't support probabilistic models

`CrossDeviceCalculator#algorithm` (line 40):

```ruby
def algorithm
  @algorithm ||= attribution_model.algorithm_class.new(touchpoints)
end
```

Compare with `Calculator#build_probabilistic_model`:

```ruby
def build_probabilistic_model
  attribution_model.algorithm_class.new(
    touchpoints,
    conversion_paths: conversion_paths
  )
end
```

`MarkovChain.new(touchpoints)` raises `ArgumentError: "Either removal_effects or conversion_paths must be provided"`. This means:
- Markov/Shapley **cannot be rerun** via the UI (RerunService uses CrossDeviceCalculator)
- Only the initial `AttributionCalculationService` (which uses Calculator) can compute them
- All existing Markov/Shapley credits are from before burst dedup existed

### Problem 3: landing_page_host only set on new sessions

`CreationService#create_or_update_session`:

```ruby
def create_or_update_session
  return update_activity! if session_reused?  # ← skips session_attributes
  return if session.persisted? && session.initial_utm.present?
  session.assign_attributes(session_attributes)
  session.save!
end
```

When session continuity reuses a session, only `last_activity_at` is updated. `landing_page_host` (part of `session_attributes`) is never applied. Sessions created before the migration stay nil forever.

This is technically correct behavior (the landing page IS the first page), but historical sessions need a backfill.

---

## Fix Plan

### Fix 1: Add burst dedup to ConversionPathsQuery

Include `BurstDeduplication` and apply it to each conversion's path. Also add `.qualified` filter.

**File:** `app/services/attribution/markov/conversion_paths_query.rb`

```ruby
module Attribution
  module Markov
    class ConversionPathsQuery
      include BurstDeduplication

      def initialize(account)
        @account = account
      end

      def call
        conversions_with_journeys
          .map { |conversion| deduped_channel_path(conversion) }
          .reject(&:empty?)
      end

      private

      attr_reader :account

      def conversions_with_journeys
        account.conversions.where.not(journey_session_ids: [])
      end

      def deduped_channel_path(conversion)
        touchpoints = sessions_for(conversion)
          .qualified
          .order(started_at: :asc)
          .where.not(channel: nil)
          .map { |s| { session_id: s.id, channel: s.channel, occurred_at: s.started_at } }

        collapse_burst_sessions(touchpoints).map { |tp| tp[:channel] }
      end

      def sessions_for(conversion)
        account.sessions.where(id: conversion.journey_session_ids)
      end
    end
  end
end
```

### Fix 2: Add probabilistic model support to CrossDeviceCalculator

Mirror the `Calculator` pattern — detect probabilistic models and pass `conversion_paths`.

**File:** `app/services/attribution/cross_device_calculator.rb`

```ruby
def algorithm
  @algorithm ||= build_algorithm
end

def build_algorithm
  return build_probabilistic_model if probabilistic_model?

  attribution_model.algorithm_class.new(touchpoints)
end

def probabilistic_model?
  attribution_model.markov_chain? || attribution_model.shapley_value?
end

def build_probabilistic_model
  attribution_model.algorithm_class.new(
    touchpoints,
    conversion_paths: conversion_paths
  )
end

def conversion_paths
  @conversion_paths ||= Markov::ConversionPathsQuery.new(account).call
end

def account
  conversion.account
end
```

### Fix 3: Backfill landing_page_host

Rake task or console script to backfill from existing `page_url` / session URL data. Sessions already store the landing page URL in their properties or can derive it from the first event URL.

Actually — sessions don't store a `page_url` column. The `landing_page_host` is derived from the `url` param at session creation time, which isn't persisted. We need to derive it from the session's first event or from the `initial_referrer` domain if the referrer is internal.

**Simpler approach:** Backfill from events. Each session's first event has a `url` property we can extract the host from.

---

## All States

### ConversionPathsQuery

| # | State | Before Fix | After Fix |
|---|-------|-----------|-----------|
| 1 | Path with burst directs `[search, direct, direct]` | 3 entries, direct appears 2x | `[search]` — directs collapsed |
| 2 | Path with suspect sessions | Included | Filtered by `.qualified` |
| 3 | Path with no directs `[search, email]` | Unchanged | Unchanged |
| 4 | Path with legitimate direct gap `[search, direct(2hr later)]` | 2 entries | 2 entries (preserved, >5min) |
| 5 | Single-session path `[search]` | 1 entry | 1 entry |
| 6 | All-direct path `[direct]` | 1 entry | 1 entry (first session immune) |
| 7 | Empty journey_session_ids | Skipped | Skipped |

### CrossDeviceCalculator

| # | State | Before Fix | After Fix |
|---|-------|-----------|-----------|
| 1 | Non-probabilistic model (linear, etc.) | Works | Works (unchanged) |
| 2 | Markov Chain model | `ArgumentError` crash | Gets `conversion_paths`, works |
| 3 | Shapley Value model | `ArgumentError` crash | Gets `conversion_paths`, works |
| 4 | No identity (nil) | Returns [] | Returns [] (unchanged) |

---

## Implementation Tasks

### Phase 1: ConversionPathsQuery fix ✅

- [x] **1.1** Include `BurstDeduplication` in `ConversionPathsQuery`
- [x] **1.2** Add `.qualified` filter to `sessions_for`
- [x] **1.3** Restructure `channel_path_for` → `deduped_channel_path` to build touchpoints and collapse
- [x] **1.4** 5 new tests: suspect filtering, burst collapse, preserve long gaps, non-direct preserved, combined

### Phase 2: CrossDeviceCalculator fix ✅

- [x] **2.1** Add `probabilistic_model?`, `build_probabilistic_model`, `build_algorithm` methods
- [x] **2.2** Add `conversion_paths` and `account` methods
- [x] **2.3** 5 new tests: linear works, markov works, shapley works, UTM enrichment, empty sessions

### Phase 3: Backfill landing_page_host

- [ ] **3.1** Write backfill script: derive host from first event URL per session
- [ ] **3.2** Run in production console
- [ ] **3.3** Verify coverage improvement

### Phase 4: Production validation

- [ ] **4.1** Rerun Markov Chain model via UI
- [ ] **4.2** Rerun Shapley Value model via UI
- [ ] **4.3** Verify Markov/Shapley direct drops from 75.6% → ~28% range
- [ ] **4.4** Verify all 8 models agree on top-3 order

---

## Key Files

| File | Changes |
|------|---------|
| `app/services/attribution/markov/conversion_paths_query.rb` | Include BurstDeduplication, add .qualified, restructure |
| `app/services/attribution/cross_device_calculator.rb` | Add probabilistic model support |
| `test/services/attribution/markov/conversion_paths_query_test.rb` | Tests for burst dedup + qualified |
| `test/services/attribution/cross_device_calculator_test.rb` | Tests for Markov/Shapley support |

---

## Definition of Done

- [ ] ConversionPathsQuery applies `.qualified` and burst dedup
- [ ] CrossDeviceCalculator supports Markov Chain and Shapley Value
- [ ] All unit tests pass
- [ ] Markov/Shapley rerun in production shows direct ≤ 35%
- [ ] All 8 attribution models agree on same top-3 channel order
- [ ] landing_page_host backfilled on historical sessions
