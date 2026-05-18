---
name: project_2026_04_22_outage_remediation
description: 2026-04-22 production outage from a ReattributionJob cache-invalidation flood inside Puma; remediation shipped same day
metadata:
  type: project
---
Full site outage 2026-04-22, roughly 00:43 to 01:17 UTC. Root cause: `Conversions::ReattributionJob` ran inside Puma (`SOLID_QUEUE_IN_PUMA: true`) and a per-`AttributionCredit` `after_commit` callback instantiated a fresh `Dashboard::CacheInvalidator` per record, each re-probing the cache backend. Roughly 76 seconds per job starved all Puma threads, the 2 GB droplet OOM-killed sshd, and recovery required stopping kamal-proxy to break the inbound flood.

**Status: SHIPPED.** `lib/specs/job_isolation_and_invalidation_fix_spec.md` (five phases) deployed 2026-04-22. Queues confirmed unpaused in prod (`SolidQueue::Pause` empty, verified 2026-05-18). `SOLID_QUEUE_IN_PUMA: false`; jobs run on a dedicated droplet.

**How to apply:**
- The remediation replaced the per-conversion `ReattributionJob` fan-out with one `Conversions::BatchReattributionJob` per identity merge.
- Follow-on problem (2026-05-18): that `BatchReattributionJob` is itself unbounded and head-of-line-blocked the worker. The April fix traded a fan-out flood for a head-of-line block. See [[project_batch_reattribution_worker_lockup]] and `lib/specs/reattribution_reliability_spec.md`.
- Incident report: `lib/specs/incidents/2026-04-22-puma-jam-reattribution-cache-flood.md`. Remediation spec still in `lib/specs/`, not yet moved to `old/`.
