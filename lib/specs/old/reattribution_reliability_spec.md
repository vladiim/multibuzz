# Reattribution Reliability Specification

**Date:** 2026-05-18
**Priority:** P1
**Status:** Complete. Shipped and verified in production 2026-05-18.
**Branch:** `fix/reattribution-reliability`

---

## Summary

Reattribution recomputes a conversion's attribution credits when something *retroactively* changes its journey: an identity merge (a previously-anonymous visitor is linked to a known user, so earlier cross-device sessions now belong to that person) or a billing unlock (previously-locked events become visible). Today this runs as a single `Conversions::BatchReattributionJob` per trigger, which is one job, an arbitrarily long list of conversion ids, processed serially.

On 2026-05-18 three of these jobs ran 24 to 64+ minutes each, saturated all three threads of the jobs worker, and froze the entire background job system for roughly 24 minutes. A customer's funnel CSV export was stranded on "Preparing your export" as collateral, because its `ExportJob` could not get a worker thread.

There are three root causes. First, the job is **unbounded**: no cap on the conversion set and no cap on per-job runtime. Second, each conversion is pathologically slow to reattribute. `ReattributionService` loads sessions one row at a time (an N+1), runs the Markov and Shapley algorithms in Ruby with no bound on journey size, and re-runs the full-account `Markov::ConversionPathsQuery` once per conversion where the sibling `RerunService` precomputes it once. Incident diagnostics showed the worker threads `idle in transaction` with the database waiting on the Ruby application and no slow SQL: the cost is in application code, not the database. Third, reattribution shares the `:default` queue and its three worker threads with latency-sensitive jobs, with no concurrency cap and no progress visibility.

This spec makes reattribution **bounded, isolated, observable, and idempotent**. A coordinator slices the work into small chunk jobs on a dedicated, concurrency-limited queue, each chunk time-bounded and tracked by a progress record. No single reattribution can ever again starve the rest of the system.

---

## Current State

### Three recompute paths, three levels of quality

mbuzz computes attribution credits in three places. All persist `AttributionCredit` rows and all call `Attribution::CrossDeviceCalculator`.

| Path | Trigger | Entry | Unit | Quality |
|------|---------|-------|------|---------|
| Initial attribution | `Conversion` `after_create_commit` | `Conversions::AttributionCalculationJob` then `AttributionCalculationService` | One job per conversion | Fine. Already per-conversion and async. |
| Reattribution | identity merge, billing unlock | `Conversions::BatchReattributionJob` then `ReattributionService` | One job, unbounded conversion list | Broken. This is the incident. |
| Model rerun | account changes an attribution model | `Attribution::RerunProcessingJob` then `Attribution::RerunService` | One job, all stale conversions | Unbounded, but has a `RerunJob` progress record and precomputed paths. |

`Attribution::RerunService` is the most mature of the three: it precomputes `Markov::ConversionPathsQuery` once (`precomputed_conversion_paths`), uses `delete_all`, and tracks progress in a `RerunJob` record. `ReattributionService` does none of this.

### Data flow (current, reattribution)

```
identity merge (Identities::IdentificationService#queue_reattribution_if_needed)
  conversions_needing_reattribution  ->  [conversion ids]   # already filtered by lookback window
  Conversions::BatchReattributionJob.perform_later(ids)     # ONE job, queue :default
    Conversion.where(id: ids).find_each                     # serial
      ReattributionService.new(conversion).call
        with_conversion_lock { delete_existing_credits; calculate_new_credits }
          delete_existing_credits -> attribution_credits.destroy_all   # per-row instantiation + callbacks
          calculate_new_credits   -> per active model:
            CrossDeviceCalculator.new(...).call                        # NO conversion_paths passed
              CrossDeviceJourneyBuilder + credit enrichment            # N+1: sessions loaded one id at a time
              markov / shapley: Markov::ConversionPathsQuery.new(account).call   # re-run per conversion
              markov / shapley algorithm                               # CPU-bound in Ruby, unbounded by touchpoints
```

For an account with a `markov_chain` or `shapley_value` model and N conversions in the batch, each conversion pays an N+1 session load and in-Ruby algorithm cost, and the full-account path query is re-run N times. None of it is bounded, so a slow per-conversion cost compounds into a job that runs for over an hour.

### The incident (2026-05-18)

`config/queue.yml` runs the jobs worker at 1 process and 3 threads. Three `BatchReattributionJob`s claimed at 00:48, 00:48, and 01:28 occupied all three threads; the two oldest ran 64+ minutes. Every newly-enqueued job, including a customer's `Dashboard::ExportJob`, sat unclaimed in `ready`. SolidQueue 1.4.0 has no per-job execution timeout (it only reclaims jobs from *dead* processes), so the hung jobs held their threads indefinitely. Full detail in `lib/memory/project_batch_reattribution_worker_lockup.md`.

All three jobs carried the **identical** 27-conversion argument list. `IdentificationService#queue_reattribution_if_needed` enqueues a fresh `BatchReattributionJob` on every `identify` call where a visitor links, with no deduplication, and SDKs commonly call `identify` repeatedly. So one identity merge produced three redundant full reattributions of the same conversions. They then contended on `ReattributionService`'s per-conversion `pg_advisory_xact_lock`, so two of the three threads spent their time blocked on Postgres advisory locks held by the third. A 27-conversion set taking 64+ minutes is the per-conversion cost compounding. Incident diagnostics showed the three worker threads `idle in transaction`, the database idle waiting on the Ruby application, the last statement a single-session-by-id lookup: the time was spent in application code (the N+1 session loads and the Markov and Shapley computation), not in a slow query.

### Key files

| File | Role |
|------|------|
| `app/jobs/conversions/batch_reattribution_job.rb` | The unbounded job. Replaced. |
| `app/jobs/conversions/reattribution_job.rb` | Dead per-conversion job. Removed. |
| `app/services/conversions/reattribution_service.rb` | Per-conversion recompute. Fixed: precomputed paths, `delete_all`, error isolation. |
| `app/services/identities/identification_service.rb` | Enqueues reattribution on merge. Rewired to the coordinator. |
| `app/services/billing/unlock_events_service.rb` | Enqueues reattribution on unlock. Rewired to the coordinator. |
| `app/services/attribution/rerun_service.rb` | Mature sibling. Reference for the pattern. |
| `app/services/attribution/cross_device_calculator.rb` | Already accepts `conversion_paths:`. |
| `config/queue.yml` | Worker and queue config. Dedicated `reattribution` worker added. |
| `config/deploy.yml` | Kamal jobs role. |

---

## Proposed Solution

Keep reattribution asynchronous, but replace the one-unbounded-job model with a **coordinator plus bounded chunks on an isolated queue**, tracked by a progress record. Borrow the maturity that already exists in `RerunService`.

### Data flow (proposed)

```
identity merge / billing unlock
  Conversions::Reattribution.enqueue(account:, conversion_ids:, trigger:)
    ReattributionBatch.create!(account:, trigger:, total: ids.size, status: :pending)
    Conversions::ReattributionCoordinatorJob.perform_later(batch.id)     # queue :reattribution

  ReattributionCoordinatorJob
    batch.processing!
    conversion_ids.each_slice(REATTRIBUTION_CHUNK_SIZE)                  # 100
      -> ReattributionChunkJob, bulk-enqueued via ActiveJob.perform_all_later

  ReattributionChunkJob.perform(batch_id, conversion_ids)                # queue :reattribution
    limits_concurrency to: 1, key: account_id                           # one account at a time
    conversion_paths = cached ConversionPathsQuery for the account       # computed about once
    each conversion (until the chunk's wall-clock budget is spent):
      ReattributionService.new(conversion, conversion_paths:).call    # statement_timeout guards SQL
      batch.increment_processed!  (or increment_failed! on a per-conversion error)
    budget spent with conversions left -> re-enqueue the remainder as a fresh chunk
    last chunk -> batch.completed!
```

### Reliability properties

| Property | How |
|----------|-----|
| Bounded | Each chunk is at most `REATTRIBUTION_CHUNK_SIZE` (100) conversions, and the chunk job stops at a wall-clock budget and re-enqueues any remainder. A `statement_timeout` guards SQL as a secondary cap. No job runs unbounded, whether the cost is in SQL or in Ruby. |
| Isolated | Dedicated `reattribution` queue with its own worker thread pool in `config/queue.yml`. Reattribution can never consume `:default` threads, so it cannot starve `ExportJob`, `AttributionCalculationJob`, and the rest. |
| Controlled fan-out | One coordinator enqueues `ceil(N / 100)` chunk jobs via `ActiveJob.perform_all_later` (bulk insert). No 92-jobs-in-a-millisecond flood (the 2026-04-22 failure mode) and no one-giant-job head-of-line block (the 2026-05-18 failure mode). |
| Concurrency-capped | `limits_concurrency to: 1, key: account_id`. One account's chunks run strictly serially, so one account's merge cannot occupy every reattribution thread. |
| Observable | A `ReattributionBatch` record carries `total`, `processed`, `failed`, `status`, and timestamps. A stuck or slow run is visible immediately. The 2026-05-18 hang was undiagnosable because no such record existed. |
| Idempotent | Each conversion's recompute is `delete_all` then recalculate inside a transaction. Re-running a chunk (retry, worker restart) reproduces identical credits. |
| Self-defending | A watchdog alerts when any job has been `claimed` longer than a threshold, catching a future stuck job before it freezes the system. |

### Make the per-conversion cost small (highest leverage, ship first)

The incident was a slow per-conversion cost with no bound. Three changes, all in `ReattributionService` and its calculators, cut that cost. They are independent of the chunking work, so they ship first as the immediate mitigation:

- **Batch-load sessions.** Incident diagnostics showed sessions loaded one id at a time. Replace the N+1 with a single batched load of the journey's sessions.
- **Precompute conversion paths.** `ReattributionService` gains a `conversion_paths:` parameter passed to `CrossDeviceCalculator`, exactly as `RerunService` already does. `Markov::ConversionPathsQuery` is computed once per chunk and cached per account in Solid Cache with a short TTL, so it is effectively computed once per burst, benefiting initial attribution and model reruns too.
- **Bound the algorithm input.** `ShapleyValue` is `O(2^channels)` evaluated against every historical path, so its cost scales with the account's conversion history. `ConversionPathsQuery` caps the path set at `MAX_PATHS` with a uniform sample (a sample preserves the coalition-completion ratio), so the in-Ruby cost cannot grow with account size.

### Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| "Can reattribution run per-conversion instead of batched?" | No, but the execution unit shrinks dramatically | The *trigger* is an identity merge, not a conversion, and the work targets *old* conversions, so there is nothing new to attach it to. But the instinct is right: the unit of work must be small. The fix is many small bounded chunk jobs, not one giant job. Initial attribution is *already* per-conversion (`AttributionCalculationJob`) and does not change. |
| Chunk vs pure per-conversion job | Chunk of 100 | One job per conversion (10k+ rows per merge) multiplies pickup, transaction, and advisory-lock overhead, and floods the queue. A 100-conversion chunk amortises overhead, bounds runtime to seconds or low minutes, and gives clean progress accounting. |
| `REATTRIBUTION_CHUNK_SIZE` | 100 | At observed per-conversion cost, 100 conversions complete well inside a minute, so any single job is short enough that a worker restart loses little. 10k conversions becomes 100 chunk jobs, trivial to enqueue and drain. |
| Conversion-paths reuse | Precompute per chunk, cache per account (Solid Cache, about 10 min TTL) | `ConversionPathsQuery` reads conversion *journeys*, which reattribution does not change (only new conversions do), so a short TTL is safe. Caching collapses N queries to about 1 across the whole burst and also speeds initial attribution and model reruns. |
| Progress record | New `ReattributionBatch` model | Mirrors the proven `RerunJob` pattern. Without it the 2026-05-18 hang was undiagnosable from the data. |
| Coalesce duplicate triggers | Skip enqueue when an unfinished `ReattributionBatch` already covers the same conversions | The 2026-05-18 incident enqueued the identical 27-conversion reattribution three times because `identify` is called repeatedly. Idempotent *execution* is not enough; the *trigger* must dedupe, or redundant jobs pile up and contend on the per-conversion advisory lock. |
| Queue isolation | Dedicated `reattribution` queue plus its own worker | The 2026-04-22 remediation moved jobs off Puma. This moves heavy reattribution off the `:default` thread pool. Latency-sensitive jobs keep their threads no matter how much reattribution is queued. |
| Stuck-job protection | Chunk wall-clock budget, plus a `statement_timeout`, plus a claimed-duration watchdog alert | SolidQueue 1.4.0 has no per-job execution timeout and only prunes jobs from *dead* processes, so a live worker on a slow job is invisible to it. The 2026-05-18 hang was in Ruby, not SQL, so a `statement_timeout` alone would not have caught it. The wall-clock budget is the real bound; the watchdog is the catch-all for any future hang. |
| Generalising `RerunService` onto this pipeline | Out of scope, recommended follow-up | `RerunService` has the same unbounded-loop shape. Converging all three paths onto the chunked primitive is the right end state but is a larger refactor. This spec fixes the path that caused the incident. |

---

## All States

| State | Condition | Expected behaviour |
|-------|-----------|--------------------|
| Happy path | Merge, few conversions need reattribution | One coordinator, 1 chunk, batch `completed`, credits recomputed |
| Large merge | 50k conversions need reattribution | 500 chunk jobs on the `reattribution` queue, drained under the concurrency cap; `:default` queue unaffected throughout |
| Nothing to do | `conversion_ids` empty | No `ReattributionBatch`, no coordinator enqueued (preserves the current `if ids.any?` guard) |
| Duplicate trigger | A second `identify` for the same merge arrives while a batch is unfinished | `enqueue` finds the existing unfinished `ReattributionBatch` and returns it; no second batch, no redundant work |
| Per-conversion error | One conversion raises mid-chunk | Logged, `batch.increment_failed!`, chunk continues. Mirrors `AttributionCalculationService#calculate_model_safely`. |
| Chunk over budget | The wall-clock budget is spent with conversions left | The chunk stops and re-enqueues the remainder as a fresh chunk; the thread is released; no job runs unbounded |
| Slow SQL | A single statement exceeds `statement_timeout` | That conversion fails fast and is counted; the chunk continues |
| Chunk retry | Chunk job retried (`retry_on`) or worker restarted mid-chunk | `delete_all` then recalculate is idempotent, so reprocessed conversions yield identical credits; `processed` may overcount slightly, which is acceptable and advisory |
| Concurrent merges, same account | Two merges for one account | `limits_concurrency key: account_id` serialises their chunks; the per-conversion advisory lock is the final guard against a double-write race |
| Concurrent merges, different accounts | Two accounts merging at once | Chunks run in parallel up to the `reattribution` worker thread count |
| Worker fully busy | All `reattribution` threads occupied | Further chunks wait in `ready` on the `reattribution` queue; `:default` jobs keep running on their own worker |

---

## Implementation Tasks

### Phase 1: Make the per-conversion cost small (ship first, standalone mitigation)

- [x] **1.1** RED: test `ReattributionService` passes `conversion_paths:` through to `CrossDeviceCalculator` and does not run `ConversionPathsQuery` per conversion
- [x] **1.2** Add a `conversion_paths:` keyword to `ReattributionService#initialize`; thread it into `calculator_credits`
- [x] **1.3** Fix the N+1: `Markov::ConversionPathsQuery` batch-loads every journey's sessions in one query (`SESSION_LOAD_BATCH_SIZE` slices) instead of one query per conversion
- [x] **1.4** Replace `destroy_all` with `delete_all` in `delete_existing_credits` (credits have no destroy side effects beyond the cache callback, which is already suppressed)
- [x] **1.5** Isolate per-conversion failures: `ReattributionService#calculate_model_safely` wraps each model calc, so one failing model logs and returns `[]` instead of aborting the conversion
- [x] **1.6** Add per-account caching of `Markov::ConversionPathsQuery` via `.cached_for` (Solid Cache, 10 min TTL); `CrossDeviceCalculator` and `RerunService` read it
- [x] **1.7** Cap the historical path set at `MAX_PATHS` (uniform sample) in `ConversionPathsQuery` so the `O(2^channels)` Shapley / Markov cost cannot scale with an account's full conversion history
- [x] **1.8** Run the full suite, confirm no regressions (3945 tests, 0 failures)

### Phase 2: `ReattributionBatch` progress record

- [x] **2.1** Migration: `reattribution_batches` (account, trigger enum, total, processed, failed, status enum, timestamps); `prefixed_ids` prefix `rbatch`
- [x] **2.2** `ReattributionBatch` model with concerns (`Enums`, `Relationships`, `Validations`, `Scopes`); `increment_processed!`, `increment_failed!`, status transitions; mirror `RerunJob`
- [x] **2.3** Tests for state transitions and counters (10 tests)

### Phase 3: Coordinator and chunk jobs

- [x] **3.1** `ReattributionCoordinator` slices `conversion_ids` into `CHUNK_SIZE` (100) chunks and bulk-enqueues chunk jobs via `ActiveJob.perform_all_later`
- [x] **3.2** `Conversions::ReattributionCoordinatorJob` (`queue_as :reattribution`), a thin wrapper over `ReattributionCoordinator`
- [x] **3.3** `Conversions::ReattributionChunkJob` (`queue_as :reattribution`) over `ChunkReattribution`: cached precomputed paths, a wall-clock budget that re-enqueues the remainder, a `statement_timeout` for SQL, `ReattributionBatch` counter updates
- [x] **3.4** `Conversions::Reattribution.enqueue` entry point creates the batch and enqueues the coordinator (needed a `conversion_ids` column on `reattribution_batches`, added by migration)
- [x] **3.5** Coalesce duplicate triggers: `enqueue` returns an existing unfinished `ReattributionBatch` with the same sorted `conversion_ids` instead of creating a second
- [x] **3.6** `IdentificationService` and `UnlockEventsService` rewired to `Conversions::Reattribution.enqueue`
- [x] **3.7** `BatchReattributionJob` and the dead `ReattributionJob` deleted
- [x] **3.8** Tests: coordinator slicing, chunk processing + budget re-enqueue, entry-point coalescing, caller batch creation; idempotent re-run covered by the existing `ReattributionService` double-reattribution test

### Phase 4: Queue isolation

- [x] **4.1** `config/queue.yml`: the default worker handles `[default, low, solid_queue_recurring]` and never `reattribution`; a dedicated `reattribution` worker has its own 2 threads
- [x] **4.2** `config/deploy.yml`: `bin/jobs` on the jobs role boots both workers from `queue.yml` (documented inline)
- [x] **4.3** `limits_concurrency to: 1` on `ReattributionChunkJob`, keyed by batch (per-batch is per-account given Phase 3 coalescing), `duration` exceeds the chunk budget

### Phase 5: Watchdog (the catch-all safety net)

A wall-clock budget and a `statement_timeout` bound the *known* slow paths. The watchdog catches *any* future hang, in Ruby or SQL, in reattribution or any other job.

`Infrastructure::QueueDepthAlert` already alerts when a job has been `claimed` past `DEFAULT_STUCK_DURATION` (`report_stuck_jobs!`), with tests. The 2026-05-18 gap was not a missing check: the watchdog job runs on the `:default` worker, which was itself jammed, so it never ran. Phase 4 isolates reattribution off `:default`, and the reattribution worker also polls the default-side queues at lower priority, so a jam on either worker pool cannot silence the watchdog.

- [x] **5.1** Claimed-too-long alerting confirmed in `QueueDepthAlert#report_stuck_jobs!`; watchdog made un-starvable via the fallback worker in `config/queue.yml`
- [x] **5.2** Existing test "reports stuck jobs when any claim is older than stuck_duration" covers the alert

---

## Testing Strategy

### Unit and integration tests (no mocks, per the no-mocks rule)

| Test | File | Verifies |
|------|------|----------|
| Precomputed paths threaded through | `test/services/conversions/reattribution_service_test.rb` | `ConversionPathsQuery` not called per conversion |
| `delete_all` used | same | No per-credit instantiation |
| Per-conversion error isolation | same | One bad conversion does not abort the rest |
| Coordinator slicing | `test/jobs/conversions/reattribution_coordinator_job_test.rb` | N ids become `ceil(N/100)` chunk jobs on `:reattribution` |
| Chunk progress | `test/jobs/conversions/reattribution_chunk_job_test.rb` | `processed` and `failed` counters; batch `completed` on the last chunk |
| Idempotent re-run | same | Re-running a chunk yields identical credits |
| Concurrency key | same | `limits_concurrency` keyed by `account_id` |
| Cross-account isolation | all of the above | A batch never touches another account's conversions or credits |
| Watchdog | `test/services/infrastructure/queue_depth_alert_test.rb` | Alert fires on a long-claimed execution |

### Manual QA (dev)

1. Seed an account with a `markov_chain` model and a few hundred conversions across two visitors.
2. Identify a visitor (`POST /api/v1/identify`) to trigger a merge.
3. Confirm a `ReattributionBatch` is created, chunk jobs land on `:reattribution`, `processed` climbs, and the batch reaches `completed`.
4. While it runs, enqueue an `ExportJob` and confirm it completes promptly, which proves queue isolation.

---

## Definition of Done

- [x] All phases complete
- [x] Tests pass (unit and integration), no regressions (3964 tests, 0 failures)
- [x] Verified in production: a reattribution batch completes in seconds with `processed == total`
- [x] `BatchReattributionJob` and `ReattributionJob` removed
- [x] `lib/docs/architecture/reattribution_pipeline.md` added
- [x] `lib/docs/BUSINESS_RULES.md` reviewed: reattribution timing is internal, no user-visible behaviour changed
- [x] Spec archived to `lib/specs/old/`
- [x] `lib/memory/project_batch_reattribution_worker_lockup.md` updated

---

## Out of Scope

- **Export status-page bugs.** The stranded spinner (no failure broadcast and no polling in `show.html.erb`), the retry re-attach `RecordNotUnique` on `index_active_storage_blobs_on_key`, and the `Date::Error` on custom export ranges are real but separate. Own spec.
- **Converging `RerunService`** onto the chunked primitive. Recommended follow-up, larger refactor.
- **Rails 8.1 `ActiveJob::Continuable`.** Native interruptible and resumable jobs would let a chunk survive a deploy mid-run. mbuzz is on Rails 8.0.5; revisit when upgrading. The coordinator-plus-chunk design is the same idea built by hand.
- **Raising `JOB_CONCURRENCY` or resizing the droplet.** Capacity tuning is tracked separately in `db_resilience_spec.md`.
