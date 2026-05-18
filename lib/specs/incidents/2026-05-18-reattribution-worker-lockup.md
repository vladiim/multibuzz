# Reattribution Worker Lockup Investigation

**Date:** 2026-05-18
**Status:** Resolved. Final fix verified in production 2026-05-18: a 27-conversion batch completed in seconds with `processed == total` and no overshoot.

---

## What Happened

The production background-job system froze for roughly 24 minutes. Three `Conversions::BatchReattributionJob`s, each reattributing an identity's conversions, ran for 24 to 64+ minutes and occupied all three threads of the single jobs worker. Every other job, including a customer's CSV export, sat unrun.

The reattribution pipeline was then rebuilt over five phases to be bounded, isolated, and observable (`lib/specs/old/reattribution_reliability_spec.md`). The rebuilt pipeline shipped with a second-order defect, a finished batch could be reprocessed many times over, which was caught in production testing and fixed.

---

## Timeline

| Time (UTC, 2026-05-18) | Event |
|------|------|
| ~00:48 | Two `BatchReattributionJob`s claimed; a third at ~01:28. Each runs unbounded. |
| ~01:28 to 01:52 | All three jobs-worker threads saturated. No other job runs. A customer funnel export is stranded on "Preparing your export". |
| ~02:2x | Recovered: stuck jobs discarded, jobs container restarted, `default` queue unpaused. |
| (same day) | Five-phase fix built with TDD, full suite green, deployed (`febbc54`). |
| ~08:16 | Verification batch enqueued. Observed reprocessing its 27 conversions roughly three times over. |
| ~08:5x | Reprocessing root-caused; fix built with TDD and deployed (`bbbf44c`). |

---

## Root Cause

Three layers caused the freeze.

**1. The job was unbounded.** `BatchReattributionJob` reattributed every conversion of an identity in one job: no row cap, no runtime cap, no statement timeout. `SolidQueue` has no per-job execution timeout, so a slow job holds its worker thread indefinitely.

**2. The per-conversion cost was pathological.** `Conversions::ReattributionService` re-ran the full-account `Markov::ConversionPathsQuery` once per conversion, and that query loaded sessions one row at a time (an N+1). The `shapley_value` algorithm is `O(2^channels)` evaluated against every historical conversion path, recomputed from scratch for every conversion. A single conversion could take 10+ minutes of Ruby CPU.

**3. No isolation.** Reattribution shared the one `:default` worker (three threads) with every latency-sensitive job, so a slow reattribution starved exports, attribution, and even the monitoring job that would otherwise have alerted.

**Second-order defect in the rebuilt pipeline.** Per-conversion cost was still high enough that a chunk job ran longer than its `limits_concurrency` `duration`. `SolidQueue` then released the concurrency lock and a duplicate chunk ran concurrently, and nothing checked whether the batch was already complete. A 27-conversion batch was processed roughly three times.

---

## Fix Applied

Full design and phase detail: `lib/specs/old/reattribution_reliability_spec.md`.

| Phase | Change |
|-------|--------|
| 1 | `ConversionPathsQuery` batch-loads sessions in one query and caches per account; `ReattributionService` accepts precomputed paths and isolates per-model failures |
| 2 | `ReattributionBatch` progress record, so every run is observable |
| 3 | Coordinator slices work into 100-conversion `ReattributionChunkJob`s; each chunk has a wall-clock budget and re-enqueues its remainder; trigger coalescing |
| 4 | Dedicated `reattribution` queue and worker; the default worker never touches it |
| 5 | `QueueDepthAlert` watchdog kept un-starvable by the worker topology |

Post-deploy fix (`bbbf44c`) for the reprocessing defect:

- `ShapleyValue` memoises `coalition_value`: at most `2^channels` distinct coalitions instead of tens of thousands of recomputations.
- `ConversionPathsQuery` caps historical paths at 500, down from 5000.
- `ReattributionCoordinator` atomically claims its batch with a row lock, so a duplicate coordinator cannot enqueue a second set of chunks.
- `ChunkReattribution` returns immediately once the batch is completed.

---

## Prevention

- Reattribution is physically isolated on its own queue and worker. A slow reattribution can no longer starve anything else, including the watchdog.
- Every unit of work is bounded: 100-conversion chunks, a wall-clock budget, a statement timeout, `limits_concurrency`.
- The `ReattributionBatch` record makes a stuck or slow run visible immediately. The original freeze was undiagnosable because nothing tracked it.
- The `QueueDepthAlert` watchdog detects long-claimed jobs and can no longer be silenced by a jammed worker.
- A finished batch is idempotent against re-runs (coordinator claim plus chunk completed-guard), with regression tests.

---

## Outstanding

1. **Production re-test: done.** A 27-conversion batch completed in seconds with `processed == total` exactly, no overshoot. The speed and reprocessing fixes are verified on real account data.
2. **Per-batch coalition precompute (recommended optimisation, not required).** Shapley's `coalition_value` and Markov's removal effects depend only on the account's path history, not the individual conversion. They could be computed once per batch and shared across all conversions, rather than memoised per conversion. The deployed per-conversion memoisation already makes each conversion fast; this would make a whole batch cheaper still. Safe to schedule as ordinary follow-up work.
3. **Export status-page bugs** found during recovery (no failure broadcast, retry re-attach `RecordNotUnique`, `Date::Error` on custom ranges) remain for their own spec.
