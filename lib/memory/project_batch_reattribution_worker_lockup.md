---
name: project_batch_reattribution_worker_lockup
description: 2026-05-18 incident, Conversions::BatchReattributionJob runs unbounded and head-of-line-blocks the 3-thread jobs worker, freezing all background jobs
metadata:
  type: project
---
2026-05-18 ~01:28 to 01:52 UTC the prod background job system was fully frozen. Root cause: `Conversions::BatchReattributionJob` (introduced by the 2026-04-22 remediation, see [[project_2026_04_22_outage_remediation]]) is unbounded. It processes every conversion for one identity merge in a single job with no row cap and no statement timeout. Worse, `Conversions::ReattributionService` recomputes the full-account Markov `ConversionPathsQuery` once per conversion (O(N^2)), while the sibling `Attribution::RerunService` already precomputes it once. Incident diagnostics showed the worker threads `idle in transaction` with the database waiting on the Ruby application: the per-conversion cost is in application code (an N+1 session load and the in-Ruby Markov and Shapley algorithms), not slow SQL, so a `statement_timeout` would not catch it. There is also no trigger deduplication: `Identities::IdentificationService` enqueues a fresh job on every `identify` call, so the incident enqueued the identical 27-conversion set three times, and the redundant jobs then blocked each other on `ReattributionService`'s per-conversion `pg_advisory_xact_lock`. Three instances ran 24 to 64+ minutes and occupied all 3 worker threads (`config/queue.yml`: 1 process x 3 threads, `JOB_CONCURRENCY` default 1). SolidQueue 1.4.0 has no per-job execution timeout (it only reclaims jobs from dead processes), so the hung jobs held their threads indefinitely and head-of-line-blocked everything else.

Surfaced via a funnel CSV export stuck on "Preparing your export": the `Dashboard::ExportJob` sat in `ready`, unclaimed, because no thread was free. The export pipeline itself was not at fault.

**Why:** the April fix traded the old per-conversion fan-out flood for a head-of-line block. Same underlying gap: a single heavy reattribution unit with no bound.

**How to apply:**
- Fix specced in `lib/specs/reattribution_reliability_spec.md`: coordinator plus bounded chunk jobs, dedicated `reattribution` queue, per-account concurrency cap, `ReattributionBatch` progress record, chunk wall-clock budget, claimed-duration watchdog. Phase 1 (batch-load sessions, precomputed conversion paths, bounded algorithm input) is the standalone per-conversion mitigation and should ship first.
- Recovery procedure when a job lockup recurs: record the stuck jobs' arguments, `discard` the job rows one at a time, then restart the jobs container so the threads free without the jobs retrying.
- Separate lower-priority export bugs found in the same session, each wants its own spec: the export status page cannot surface failure (no broadcast on the `ExportJob` rescue path, no polling in `show.html.erb`); retry re-attach `RecordNotUnique` on `index_active_storage_blobs_on_key`; `Date::Error` from `Dashboard::DateRangeParser` on custom date ranges.
