# Production Outage — Puma Jam from ReattributionJob Cache-Invalidation Flood

**Date:** 2026-04-22
**Status:** Resolved (recovery only — remediation pending)
**Severity:** Critical (full site outage, ~30+ minutes user-visible)

---

## What Happened

A burst of `Conversions::ReattributionJob` enqueued at the same millisecond ran inside Puma (because `SOLID_QUEUE_IN_PUMA: true`). Each job triggered an `after_commit` cache invalidation per `AttributionCredit` write — thousands of `Dashboard::CacheInvalidator` calls per job, each re-probing whether the cache backend supports `delete_matched`. Puma threads were starved for ~76 seconds per job. The 2GB droplet ran out of memory headroom, the OOM killer took out `sshd`, and the box became unreachable at SSH while still listening on TCP. After reboot, residual SDK traffic from Cloudflare slammed Puma faster than it could drain (~1,924 sockets in CLOSE_WAIT), so every container restart re-jammed within seconds. Recovery required stopping `kamal-proxy` to cut the inbound flood, restarting the web container in the quiet, then resuming the proxy.

---

## Timeline

| Time (UTC) | Event |
|------------|-------|
| 00:43:01 | 92 `Conversions::ReattributionJob` enqueued in the same millisecond (also 140 `AttributionCalculationJob`, 140 `PropertyKeyDiscoveryJob`, 722 `DataIntegrity::SurveillanceJob`) |
| 00:43:01+ | First `ReattributionJob` claimed by Solid Queue inside Puma — runs 76,401 ms |
| ~00:44 | Puma worker threads starved; SDK requests (`/api/v1/sessions`, `/api/v1/events`) begin returning 502 via `Thruster` ("context canceled") |
| ~00:45 | Memory crosses ~88% on the 2GB droplet; Linux OOM killer fires |
| ~00:45 | `sshd` dies; SSH banner timeout from operator workstation; site returns Cloudflare 504 |
| 01:09 | Operator reboots droplet via DigitalOcean control panel |
| 01:12 | Containers restart; web container picks up next `ReattributionJob`, re-jams within seconds |
| 01:14 | Operator pauses all Solid Queue queues (`default`, `low`, `solid_queue_recurring`) via `SolidQueue::Pause` |
| 01:15 | Container restarted again — but 5 jobs claimed during boot window before pause registered; Puma still jammed by inbound SDK flood + 1,924 CLOSE_WAIT sockets |
| 01:16 | `kamal-proxy` stopped to cut inbound traffic |
| 01:16 | Web container restarted in the quiet — Puma now responsive (200 OK in <20 ms) |
| 01:17 | `kamal-proxy` restarted; site back online |

---

## Root Cause

### The Hot Loop

Every `AttributionCredit` write (create / update / destroy) triggers an `after_commit` callback that constructs a fresh `Dashboard::CacheInvalidator` instance:

```ruby
# app/models/concerns/attribution_credit/callbacks.rb
after_commit :invalidate_dashboard_cache, on: [ :create, :update, :destroy ]

def invalidate_dashboard_cache
  Dashboard::CacheInvalidator.new(account).call
end
```

Each `CacheInvalidator#call` iterates two sections (`conversions`, `funnel`) and, for each one, instance-memoizes a `supports_delete_matched?` probe that **actually calls `Rails.cache.delete_matched("__test_pattern_that_wont_match__")`** to test the backend. SolidCache doesn't support it, so `NotImplementedError` fires every time, then a logger line is written.

`Conversions::ReattributionService#run` calls `attribution_credits.destroy_all` then `attribution_credits.create!` for every credit produced by every active attribution model. For one conversion with N active models × M credits per model, that is **2 × N × M cache-invalidator instantiations and 2 × 2 × N × M cache-backend probes**. For the batch of 92 conversions in tonight's flood, this produced thousands of redundant cache calls and tens of thousands of logger lines per job.

### The Fan-Out

`Conversions::ReattributionJob` is enqueued one-per-conversion from two sites:

| Caller | Behaviour |
|--------|-----------|
| `app/services/identities/identification_service.rb:66` | `Conversions::ReattributionJob.perform_later(conversion.id)` per affected conversion when an identity is created/merged |
| `app/services/billing/unlock_events_service.rb:61` | Same per conversion when billing unlocks events |

Both fan out without batching, throttling, or jitter. A single identity merge or billing event for a high-conversion account → dozens to hundreds of jobs at once.

### The Architecture That Amplified It

| Setting | File | Value | Why It Hurt |
|---------|------|-------|-------------|
| `SOLID_QUEUE_IN_PUMA` | `config/deploy.yml:43` | `true` | Job latency = web latency. The 76 s job blocked all 6 Puma worker threads. |
| Single droplet, 2 GB | DigitalOcean | 2 GB RAM, no swap | OOM killer = instant SSH death (no graceful degradation). |
| `kamal-proxy` v0.9.0 | running container | < v0.9.2 required by current Kamal CLI | Locks us out of `kamal deploy` until `kamal proxy reboot`. |

The April 13 `lib/specs/db_resilience_spec.md` flagged Solid-Queue-in-Puma as Phase 4A and explicitly deferred it: *"Not the root cause of the current crashes. Good practice as we grow, not urgent."* Tonight proved that judgement wrong.

---

## Fix Applied (Tonight, Recovery Only)

| Action | Effect |
|--------|--------|
| Reboot droplet via DO control panel | Restored SSH after OOM-induced sshd death |
| `SolidQueue::Pause.find_or_create_by!(queue_name: q)` for `default`, `low`, `solid_queue_recurring` | Stops all Solid Queue dispatching; queued jobs sit safely in DB |
| `docker stop kamal-proxy` → `docker restart` web → `docker start kamal-proxy` | Cleared 1,924 CLOSE_WAIT sockets and the request flood that jammed Puma on every restart |

**Current state at time of writing:**

- Site responding normally
- All Solid Queue queues paused — **no jobs run until queues are unpaused**
- 91 `Conversions::ReattributionJob` + 140 `AttributionCalculationJob` + 140 `PropertyKeyDiscoveryJob` + 722 `DataIntegrity::SurveillanceJob` queued and waiting
- `kamal deploy` will fail until `kamal proxy reboot` is run (v0.9.0 → v0.9.2)

**Unpausing without remediation will reproduce the outage immediately.**

---

## Prevention

Tracked in `lib/specs/job_isolation_and_invalidation_fix_spec.md`. Five phases, all targeted for completion same day as this incident:

1. Class-level memoisation of `supports_delete_matched?` (kills the hot probe)
2. Batched cache invalidation in `Conversions::ReattributionService` (one `CacheInvalidator#call` per conversion, not per credit)
3. Coalesce per-conversion `ReattributionJob` enqueues into one job per identity (kills the 92-at-once fan-out)
4. Move Solid Queue out of Puma — `SOLID_QUEUE_IN_PUMA: false` + dedicated Kamal role/accessory running `bin/jobs` (job latency cannot ever cause web latency again)
5. Operational: `kamal proxy reboot` (unblock deploys), 2 GB swap on droplet (OOM degrades instead of killing sshd), drain or delete the queued backlog, unpause queues

Phase 4A of `db_resilience_spec.md` is **superseded by Phase 4 of the new spec** and promoted from "future" to P0.

---

## Lessons

- **Cache invalidation in `after_commit` callbacks is dangerous in any code path that writes records in a loop.** Either batch the invalidation at the service layer with `skip_callback`, or make the callback cheap enough that N× is fine.
- **`SOLID_QUEUE_IN_PUMA: true` is a deferred outage.** Web stays healthy only as long as no job is slow. The first time a job is slow, every web request times out.
- **Fan-out enqueueing without batching is a load-test against your own infrastructure.** Any code that does `things.each { Job.perform_later(...) }` should batch instead.
- **No swap on a small droplet means OOM = SSH death**, not graceful degradation. The difference is "I can investigate" vs "I have to reboot blind."
- **Cloudflare's traffic flood will re-jam a freshly-restarted Puma in seconds.** Recovery from a Puma jam requires cutting inbound traffic at the proxy layer first.
