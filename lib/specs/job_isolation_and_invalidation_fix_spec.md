# Job Isolation & Cache-Invalidation Fix Specification

**Date:** 2026-04-22
**Priority:** P0
**Status:** Complete — all phases deployed 2026-04-22
**Branch:** `feature/session-bot-detection` (or new branch — see Phase 0)

---

## Summary

The 2026-04-22 production outage (`lib/specs/incidents/2026-04-22-puma-jam-reattribution-cache-flood.md`) was caused by `Conversions::ReattributionJob` running inside Puma and triggering thousands of redundant `Dashboard::CacheInvalidator` calls per job, each re-probing the cache backend. Web threads were starved for ~76 seconds per job; the 2GB droplet OOM-killed `sshd`; recovery required stopping `kamal-proxy` to break the request flood. Five fixes, ordered by blast radius, eliminate the hot loop, kill the per-record fan-out, and isolate jobs from web. All five must ship today; queues stay paused until they are deployed.

This spec **supersedes Phase 4A of `lib/specs/db_resilience_spec.md`** (which deferred Solid-Queue-out-of-Puma as "not urgent").

---

## Current State

### The Hot Path (Why One Job Took 76 Seconds)

```
Conversions::ReattributionService#run (per conversion)
  delete_existing_credits          → conversion.attribution_credits.destroy_all
                                     → for each AttributionCredit: after_commit :invalidate_dashboard_cache
                                       → Dashboard::CacheInvalidator.new(account).call
                                         → SECTIONS.each (2 sections) → instance-memoised supports_delete_matched?
                                         → first call per instance: Rails.cache.delete_matched("__test_pattern_that_wont_match__")
                                         → rescues NotImplementedError, logs "Skipping invalidation for ..."
  calculate_new_credits            → for each active model × each credit: AttributionCredit.create!
                                     → same callback chain
```

For a conversion with 5 active models × ~10 credits per model:
- ~50 destroys + ~50 creates = 100 callback fires
- Each fire instantiates a fresh `Dashboard::CacheInvalidator` (no class-level memoisation)
- Each instance probes the backend twice (once per section)
- = ~200 `delete_matched` calls + ~200 logger lines per conversion
- For tonight's batch of 92 conversions: ~18,400 cache calls, ~18,400 logger lines, run inside Puma

### The Fan-Out

| File | Line | Pattern |
|------|------|---------|
| `app/services/identities/identification_service.rb` | 66 | `conversions.each { Conversions::ReattributionJob.perform_later(_1.id) }` |
| `app/services/billing/unlock_events_service.rb` | 61 | `conversions.each { Conversions::ReattributionJob.perform_later(_1.id) }` |

One identity merge for an account with 92 conversions = 92 jobs enqueued in the same millisecond. No batching, no jitter, no coalescing.

### The Architecture That Amplified It

| File | Line | Setting | Today's Value |
|------|------|---------|---------------|
| `config/deploy.yml` | 43 | `SOLID_QUEUE_IN_PUMA` | `true` (jobs run inside Puma → job latency = web latency) |
| `config/puma.rb` | 39 | `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]` | active in production |
| DigitalOcean | — | Droplet RAM | 2 GB, no swap (OOM = sshd death) |
| Production server | — | `kamal-proxy` version | v0.9.0 (Kamal CLI requires ≥ v0.9.2) → blocks deploy |

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/services/dashboard/cache_invalidator.rb` | Cache-invalidation entry point | Class-level `supports_delete_matched?`; conditional logger |
| `app/services/conversions/reattribution_service.rb` | Per-conversion reattribution | Skip per-credit callbacks; invalidate once at end |
| `app/services/identities/identification_service.rb` | Identity merge → fan-out enqueue | Replace per-conversion fan-out with one `BatchReattributionJob` per identity |
| `app/services/billing/unlock_events_service.rb` | Billing unlock → fan-out enqueue | Same |
| `app/jobs/conversions/batch_reattribution_job.rb` | **New** | Processes all conversions for an identity in one job |
| `config/deploy.yml` | Kamal config | `SOLID_QUEUE_IN_PUMA: false`; add `roles:` or accessory for jobs |
| `config/puma.rb` | Puma config | Plugin already env-guarded — no change |

---

## Proposed Solution

Five sequential phases. Phases 1–3 are code; Phase 4 is infra; Phase 5 is operational. Queues remain paused throughout 1–4. Phase 5 unpauses.

### Phase 1: Class-Level Cache-Backend Probe

`Dashboard::CacheInvalidator#supports_delete_matched?` is currently instance-memoised, so every callback fire re-probes. Move it to a class-level constant computed once at boot.

```ruby
module Dashboard
  class CacheInvalidator
    SECTIONS = %w[conversions funnel].freeze

    DELETE_MATCHED_SUPPORTED = begin
      Rails.cache.delete_matched("__cache_invalidator_probe__")
      true
    rescue NotImplementedError
      false
    end

    def initialize(account)
      @account = account
    end

    def call
      return unless DELETE_MATCHED_SUPPORTED
      SECTIONS.each { |section| Rails.cache.delete_matched("dashboard/#{section}/#{account.prefix_id}/*") }
    end

    private

    attr_reader :account
  end
end
```

When the backend doesn't support `delete_matched`, `#call` is now a no-op (one method call, no logger, no probe). The per-job log spam is eliminated.

### Phase 2: Batched Invalidation in `ReattributionService`

`AttributionCredit::Callbacks` fires `after_commit` on every record write. In a service that destroys N and creates M for a single conversion, the right answer is to skip per-record callbacks and invalidate once.

```ruby
module Conversions
  class ReattributionService < ApplicationService
    # ...

    private

    def run
      return error_result([ "Conversion has no identity" ]) unless identity

      with_conversion_lock do
        AttributionCredit.skip_callback(:commit, :after, :invalidate_dashboard_cache) do
          delete_existing_credits
          calculate_new_credits
        end
      end

      Dashboard::CacheInvalidator.new(conversion.account).call
      success_result(credits_by_model: credits_by_model)
    end
  end
end
```

`skip_callback` is scoped to the block. Other writers of `AttributionCredit` outside this service still get the per-record callback, so dashboard invalidation behaviour is unchanged everywhere else.

**Edge case:** if the service raises inside the block, `skip_callback` still un-skips on exit (Active Support `skip_callback` is lexically scoped). The cache simply isn't invalidated for the failed run, which is acceptable — the conversion's credits are unchanged on rollback.

### Phase 3: Coalesce `ReattributionJob` Fan-Out

Both call sites enqueue one job per conversion. Replace with one `BatchReattributionJob` per call site invocation, taking the list of `conversion_ids` so the caller keeps control of which conversions to include (preserves the IdentificationService lookback filter).

```ruby
# app/jobs/conversions/batch_reattribution_job.rb (new)
module Conversions
  class BatchReattributionJob < ApplicationJob
    queue_as :default

    def perform(conversion_ids)
      Conversion.where(id: conversion_ids).find_each do |conversion|
        ReattributionService.new(conversion).call
      end
    end
  end
end
```

Update both call sites:

```ruby
# app/services/identities/identification_service.rb
def queue_reattribution_if_needed
  ids = conversions_needing_reattribution.map(&:id)
  Conversions::BatchReattributionJob.perform_later(ids) if ids.any?
end

# app/services/billing/unlock_events_service.rb
def enqueue_reattribution_jobs
  ids = conversions_in_locked_period.pluck(:id)
  Conversions::BatchReattributionJob.perform_later(ids) if ids.any?
end
```

`Conversions::ReattributionJob` (the per-conversion job) stays — kept for explicit single-conversion reattribution and for the queued backlog. We do not remove it in this spec.

`find_each` keeps memory bounded. Per-conversion failure is contained (one bad conversion doesn't kill the batch — `ApplicationService` rescues internally and returns an error result).

**Contract decision: `conversion_ids` (not `identity_id`)** — the original spec proposed `identity_id`. Switched to `conversion_ids` because IdentificationService applies a lookback-window filter that would be lost if the job recomputed the conversion list from `identity.conversions.find_each`. Solid Queue serialises args as JSON; an array of integer IDs is ~10 bytes each, so even hundreds of IDs is well under any reasonable limit.

### Phase 4: Move Solid Queue Out of Puma — Separate Droplet

`SOLID_QUEUE_IN_PUMA: true` made job latency cause web latency. Fix is *host* isolation, not just *process* isolation: a dedicated droplet for jobs. Web crash domain is fully separated from jobs crash domain — a runaway job cannot OOM the web box, and vice versa.

**4A. Provision new droplet (operator action on DO) — DONE 2026-04-22:**

| Spec | Value | Status |
|------|-------|--------|
| Region | SFO2 | ✅ Same as web + DB (US customer base) |
| VPC | `mbuzz-sfo-vpc` | ✅ Private DB reachability verified (`10.120.0.5 → 10.120.0.3:5432` TCP_OPEN) |
| Size | s-2vcpu-4gb (2 vCPU, 4 GB) | ✅ Premium Intel NVMe |
| Image | Ubuntu 24.04 LTS | ✅ |
| Hostname | `mbuzz-jobs` | ✅ |
| Public IPv4 | `159.89.136.202` | ✅ |
| Private IPv4 | `10.120.0.5/20` | ✅ Same VPC as web (`10.120.0.2`) and DB (`10.120.0.3`) |
| SSH | root key from operator workstation | ✅ Verified |

Web droplet was also resized 2 GB → 4 GB (2 vCPU) the same day to give Puma room.

**4B. `config/deploy.yml`:**

Set `SOLID_QUEUE_IN_PUMA: false`. Add a `jobs` server role pointing at `159.89.136.202`, running `bin/jobs`.

```yaml
servers:
  web:
    - 68.183.173.51
  jobs:
    hosts:
      - 159.89.136.202
    cmd: bin/jobs

env:
  clear:
    SOLID_QUEUE_IN_PUMA: false  # was: true
    # ...
```

The jobs role does NOT get `proxy:` config — no public ingress needed. The image, env vars, secrets, and DB connection are shared automatically by Kamal.

**4C. Connection pool — NO change this round:**

Existing `pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 3 } %>` stays. **`RAILS_MAX_THREADS` is NOT bumped** in this deploy. Reason: the DB droplet is still on `max_connections=25` (per `db_resilience_spec.md`) and the app is already over capacity at idle (~37 idle connections). Bumping `RAILS_MAX_THREADS=10` would multiply pool sizes and immediately blow past the limit — a different crash, same outage. DB resize (`db_resilience_spec.md` Phase 2A: 2 GB → 4 GB, `max_connections=75`) is the prerequisite for any web-capacity bump and is tracked separately.

Net DB connection effect of THIS deploy:
- Web: **fewer** connections (Solid Queue plugin no longer running in-process — frees ~3-7 connections per worker)
- Jobs droplet: **new** source of connections (5 dbs × pool 3 ≈ 15 from one process)
- Approximate net: similar or slightly higher overall, well within "already-over-25" reality. No new crash class introduced.

**4D. Capacity bump deferred:**

The 4 GB web resize already gives Puma memory headroom. If web jams again under load after this deploy, the fix order is:

1. `db_resilience_spec.md` Phase 2A: DB droplet 2 GB → 4 GB, raise `max_connections` to 75
2. THEN bump `RAILS_MAX_THREADS=10` (or `WEB_CONCURRENCY=3`) on the web droplet
3. THEN re-deploy

Do not skip step 1.

**4E. Why separate droplet (not same host):**

| Failure | Same-host outcome | Separate-host outcome |
|---------|-------------------|------------------------|
| Job OOMs the kernel | Kernel kills processes; web container also dies | Jobs droplet reboots; web unaffected |
| Job CPU saturation | Web request latency degrades | Web unaffected |
| Job disk fills `/tmp` or logs | Web container disk also affected | Web unaffected |
| Operator restarts jobs container | Web unaffected (separate Docker) | Web unaffected |
| Operator reboots droplet | Web also offline | Web unaffected |

The cost of a 4 GB droplet (~$24/mo) is trivial against the cost of an outage like 2026-04-22.

### Phase 5: Operational Recovery

Order matters.

1. **`kamal proxy reboot`** — upgrades production proxy from v0.9.0 to current (≥ v0.9.2). Brief HTTP blip during reboot. Required before any `kamal deploy` will succeed.
2. **Add 2 GB swap on droplet** (`68.183.173.51`):
   ```
   fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
   echo '/swapfile none swap sw 0 0' >> /etc/fstab
   ```
   Turns OOM into slow-down instead of sshd death. Cheap insurance.
3. **`kamal deploy`** — ships Phases 1–4 to production.
4. **Drain the backlog** — once Phase 3 is live, the 91 queued `Conversions::ReattributionJob` are mostly redundant (they will re-attribute conversions one at a time, the slow way). Decision per Key Decisions below.
5. **Unpause queues:**
   ```ruby
   SolidQueue::Pause.where(queue_name: %w[default low solid_queue_recurring]).destroy_all
   ```
6. **Verify:** site responsive, `Conversions::ReattributionJob` (or `BatchReattributionJob`) per-call duration drops by ≥ 10× vs tonight's 76 s, no CLOSE_WAIT growth on web container.

---

## All States

| State | Condition | Expected Behaviour |
|-------|-----------|-------------------|
| Normal load | Web + light jobs | Both responsive. Web unaffected by job duration ever again. |
| Heavy reattribution batch | 1000+ conversions for one identity | One `BatchReattributionJob` runs in jobs container; web stays at full capacity |
| Cache backend doesn't support `delete_matched` | SolidCache (production) | `CacheInvalidator#call` is a no-op (one method call, no logger, no probe) |
| Cache backend supports `delete_matched` | MemoryStore (tests/dev) | `delete_matched` runs once per section per service call |
| Identity merge with no conversions | `identity.conversions.empty?` | `BatchReattributionJob` runs `find_each` over empty relation, no-ops |
| Job process crashes | Any unhandled exception | Solid Queue restarts the worker; web unaffected (separate process) |
| Web process crashes | OOM, panic | Jobs continue running; web restarts via Kamal/Docker |
| Droplet under memory pressure | Web + jobs combined > available RAM | Swap absorbs spike (slower, not dead); operator gets time to investigate |

---

## Implementation Tasks

### Phase 1 — Class-level cache-backend probe (TDD) — DONE 2026-04-22 commit `26968fe`

- [x] **1.1** RED: Test `Dashboard::CacheInvalidator#call` does not raise when backend lacks `delete_matched`
- [x] **1.2** RED: Test `#call` invokes `Rails.cache.delete_matched` once per section when supported
- [x] **1.3** RED: Test the support check is memoised at class level (one probe across many `#call`s)
- [x] **1.4** GREEN: Class-level `delete_matched_supported?` with explicit `reset_delete_matched_support!` test seam
- [x] **1.5** GREEN: Dropped the per-call logger
- [x] **1.6** Full suite green (3357 runs)

### Phase 2 — Batched invalidation in `ReattributionService` (TDD) — DONE 2026-04-22 commit `7deaa9d`

- [x] **2.1** RED: Test `ReattributionService` invokes `delete_matched` exactly `SECTIONS.size` times per call (one batched invalidator)
- [x] **2.2** RED: Test direct `AttributionCredit.create!` outside the service still triggers the callback (one invalidator per write)
- [x] **2.3** GREEN: Add `AttributionCredit.without_dashboard_cache_invalidation` thread-local toggle gated by an `unless:` callback condition (real `skip_callback` doesn't take a block)
- [x] **2.4** GREEN: Wrap the `with_conversion_lock` block in the toggle so the flag stays set through the after_commit firing
- [x] **2.5** GREEN: Explicit `Dashboard::CacheInvalidator.new(conversion.account).call` after the lock block on success
- [x] **2.6** Full suite green (3359 runs)

### Phase 3 — Coalesce fan-out (TDD) — DONE 2026-04-22 commit `8568cdf`

- [x] **3.1** RED: `Conversions::BatchReattributionJob#perform(conversion_ids)` calls `ReattributionService` once per existing id, ignores missing ids, no-ops on `[]`
- [x] **3.2** RED: `Identities::IdentificationService` enqueues exactly one `BatchReattributionJob` per call with the filtered conversion ids; none when no eligible conversions
- [x] **3.3** RED: `Billing::UnlockEventsService` enqueues one `BatchReattributionJob` covering all conversions in the locked period
- [x] **3.4** GREEN: Created `app/jobs/conversions/batch_reattribution_job.rb`
- [x] **3.5** GREEN: Updated `Identities::IdentificationService#queue_reattribution_if_needed`
- [x] **3.6** GREEN: Updated `Billing::UnlockEventsService#enqueue_reattribution_jobs`
- [x] **3.7** Full suite green (3364 runs)

### Phase 4 — Solid Queue out of Puma (separate droplet)

- [x] **4.1** Provision `mbuzz-jobs` droplet in SFO2, `mbuzz-sfo-vpc`, 2 vCPU/4 GB. Public `159.89.136.202`, private `10.120.0.5`. (DONE 2026-04-22)
- [x] **4.2** Resize web droplet (`mbuzz`) 2 GB → 4 GB, 1 vCPU → 2 vCPU. (DONE 2026-04-22)
- [x] **4.3** `kamal proxy reboot` — proxy v0.9.0 → v0.9.2. (DONE 2026-04-22)
- [x] **4.4** Edit `config/deploy.yml`: `SOLID_QUEUE_IN_PUMA: false`; add `jobs` role on `159.89.136.202` running `bin/jobs` (DONE 2026-04-22, commit `2a8afb0`)
- [x] **4.5** Fix `config/puma.rb:39` — `if ENV["SOLID_QUEUE_IN_PUMA"]` was truthy for the string `"false"`. Compare to literal `"true"`. (DONE 2026-04-22, commit `44e4fa0` — found at deploy verification: web container kept running a Solid Queue supervisor competing with the jobs droplet.)
- [x] **4.6** Confirmed `bin/jobs` exists in the Rails 8-generated image; no Dockerfile change.
- [x] **4.7** `kamal server bootstrap --hosts 159.89.136.202` (installed Docker via `get.docker.com`).
- [x] **4.8** `kamal deploy` — both containers up on `2a8afb0` then `44e4fa0`.
- [x] **4.9** Verified `SolidQueue::Process.all` shows only `159.89.136.202` host — web no longer runs Solid Queue. Pauses still hold (`["default", "low", "solid_queue_recurring"]`); 0 claimed.

### Phase 5 — Operational recovery (sequential, on production) — DONE 2026-04-22

- [x] **5.1** `kamal proxy reboot` — proxy v0.9.0 → v0.9.2 (apps-config volume preserved registrations across reboot, no manual re-deploy needed)
- [x] **5.2** 2 GB swap on `68.183.173.51` (web droplet) created and persisted to `/etc/fstab`. `swapon --show` confirms `/swapfile  file  2G  0B  -2`
- [x] **5.3** `kamal deploy` — Phases 1–3 shipped (commits `26968fe`, `7deaa9d`, `8568cdf`). Web `1.71% CPU / 436 MiB`, jobs `98.6% CPU / 494 MiB` immediately post-unpause
- [x] **5.4** Both containers verified: web on `68.183.173.51`, jobs on `159.89.136.202`, Solid Queue ONLY on jobs (after `puma.rb` env-truthy bug fix in commit `44e4fa0`)
- [x] **5.5** Drain: 513 stale per-conversion `Conversions::ReattributionJob`s collected → 54 unique `conversion_id`s extracted → deleted the 513 jobs → enqueued one `Conversions::BatchReattributionJob` covering all 54
- [x] **5.6** `SolidQueue::Pause.where(queue_name: %w[default low solid_queue_recurring]).destroy_all`
- [x] **5.7** Post-unpause: site responding 200 in 250–420 ms (5/5), CLOSE_WAIT count = 0, web idle while jobs container drains backlog at full CPU. Continued monitoring scheduled.

### Phase 6 — Alerting (so we know before users do)

**Two layers, ship both:**

**6A. In-code: `Infrastructure::QueueDepthAlert` — DONE 2026-04-22, commit `08843ea`**

Runs every 5 minutes via `config/recurring.yml`. Reports to `Rails.error` (which Solid Errors emails) when:

| Signal | Default threshold | Why |
|--------|-------------------|-----|
| Ready jobs | > 200 | Queue is backing up faster than draining |
| Stuck claim | older than 30 min | Worker died holding a claim, or job is genuinely too slow |
| Recent failures | > 10 in last hour | Something is systematically broken |

Thresholds + the metrics collaborator are constructor args so the test exercises real threshold logic against a deterministic double — no stubbing the system under test, no need to stand up Solid Queue tables in the test DB.

- [x] **6.1** `Infrastructure::QueueDepthMetrics` — pure-data collaborator that hits the Solid Queue tables
- [x] **6.2** `Infrastructure::QueueDepthAlert` with injectable thresholds + metrics provider
- [x] **6.3** `Infrastructure::QueueDepthAlertJob` thin wrapper
- [x] **6.4** Schedule entry in `config/recurring.yml` (`every 5 minutes`)
- [x] **6.5** Tests for ready / stuck / failures with deterministic doubles
- [x] **6.6** Deployed in commit `31e4ef5`; jobs container's recurring schedule lists `queue_depth_alert: every 5 minutes`
- [x] **6.7** DigitalOcean Monitoring alerts created via doctl (12 droplet + 4 uptime, all → vlad@mehakovic.com — see 6B below)
- [x] **6.8** `config.solid_errors.email_to` updated and pushed live

**6B. DigitalOcean Monitoring alerts — DONE 2026-04-22 via doctl, all routed to `vlad@mehakovic.com`**

Created 12 droplet alerts + 1 uptime check + 4 uptime alerts. (DB upgrade to 4 GB was completed the same day, so `mbuzz-db` is now in the matrix too. `mbuzz-shopify` included because it's about to host the Shopify SDK in production.)

| Resource | Metric | Trigger | Window | Why |
|----------|--------|---------|--------|-----|
| `mbuzz` (web) | Memory | > 75% | 5 min | Early warning before OOM |
| `mbuzz` (web) | CPU | > 85% | 5 min | Sustained saturation = jam coming |
| `mbuzz` (web) | Disk | > 80% | 1 hour | Plenty of warning |
| `mbuzz-jobs` | Memory | > 85% | 5 min | Higher tolerance — jobs spike on heavy workloads |
| `mbuzz-jobs` | CPU | > 95% | 30 min | Brief spikes are normal; sustained = backlog |
| `mbuzz-jobs` | Disk | > 80% | 1 hour | |
| `mbuzz-db` | Memory | > 75% | 5 min | DB cache + connections |
| `mbuzz-db` | CPU | > 85% | 5 min | |
| `mbuzz-db` | Disk | > 80% | 1 hour | DB tables grow — important on TimescaleDB |
| `mbuzz-shopify` | Memory | > 75% | 5 min | 1 GB box, OOM risk real |
| `mbuzz-shopify` | CPU | > 85% | 5 min | |
| `mbuzz-shopify` | Disk | > 80% | 1 hour | |
| Uptime check `https://mbuzz.co/up` | down (any region) | 3 min | regional | Catches "site responding but Rails dead" |
| Uptime check `https://mbuzz.co/up` | down (all regions) | 5 min | global | Confirms outage isn't regional Cloudflare flap |
| Uptime check `https://mbuzz.co/up` | latency | > 3000 ms / 5 min | n/a | Catches sustained slowness (not a hard outage) |
| Uptime check `https://mbuzz.co/up` | SSL expiry | < 14 days | n/a | Cert renewal warning |

Re-create or modify via `doctl monitoring alert create` / `doctl monitoring uptime alert create`. List existing with `doctl monitoring alert list` and `doctl monitoring uptime alert list <check-id>`.

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| CacheInvalidator no-op when unsupported | `test/services/dashboard/cache_invalidator_test.rb` | `#call` returns nil, no `delete_matched` invoked |
| CacheInvalidator calls per supported section | same | `delete_matched` called twice (one per section) for supported backend |
| CacheInvalidator probe runs once at load | same | Multiple `#call`s do not re-probe backend |
| ReattributionService invalidates once | `test/services/conversions/reattribution_service_test.rb` | `Dashboard::CacheInvalidator#call` invoked exactly once |
| ReattributionService skips callback on AC | same | `AttributionCredit#invalidate_dashboard_cache` not called during service run |
| Other AC writers still trigger callback | `test/models/attribution_credit_test.rb` | Direct `AttributionCredit.create!` outside the service still invalidates |
| BatchReattributionJob processes all conversions | `test/jobs/conversions/batch_reattribution_job_test.rb` | One `ReattributionService#call` per conversion for identity |
| BatchReattributionJob handles empty identity | same | No-op when `identity.conversions.empty?` |
| IdentificationService enqueues one batch | `test/services/identities/identification_service_test.rb` | Exactly one `BatchReattributionJob` enqueued, never `ReattributionJob` per conversion |
| UnlockEventsService groups by identity | `test/services/billing/unlock_events_service_test.rb` | One `BatchReattributionJob` per distinct identity |

### Manual QA (on production after Phase 5)

1. Site loads (`https://mbuzz.co`)
2. Dashboard renders for a real account
3. SDK `/api/v1/sessions` POST returns 2xx in < 200 ms (sample 5 requests)
4. `docker logs --tail 50 multibuzz-web-...` shows no `[CacheInvalidator] Skipping invalidation` lines
5. `docker stats` shows web container memory stable (no drift over 10 min)
6. Solid Queue jobs draining (`SolidQueue::Job.where(finished_at: nil).count` decreasing)
7. `docker ps | grep jobs` shows the new jobs container running
8. Kill a `BatchReattributionJob` mid-run (`docker restart` jobs container) — web container memory and responsiveness unchanged

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Class-level vs instance-level backend probe | Class-level constant | Probe is global to the cache backend; one process = one probe. Instance-level probes were the hot-path bug. |
| Skip-callback inside service vs remove the model callback | Skip-callback inside service | Other writers (admin tools, future code) still need automatic invalidation. The service knows the bulk-write context; the model doesn't. |
| New `BatchReattributionJob` vs modify existing `ReattributionJob` | New job | Single-conversion `ReattributionJob` is still a valid use case (manual re-runs, one-off fixes). Adding a batch sibling preserves both. |
| Same droplet for jobs role vs separate droplet | Same droplet today | The failure was *process* sharing, not *host* sharing. Same-host process separation kills the failure mode. Separate droplet is the next iteration. |
| Drain queued backlog or delete it | Delete `Conversions::ReattributionJob`s, enqueue fresh `BatchReattributionJob` per affected identity | The queued per-conversion jobs predate Phases 1–3 and would each pay full cache-callback cost. One batch job per identity covers the same conversions in a fraction of the time. |
| Add swap vs resize droplet | Add swap today, resize later if needed | Swap is free and reversible. Resize requires planned downtime and is a separate decision. |
| Defer LB / multi-node | Out of scope | One healthy node is more stable than two badly-tuned ones. Earn the LB by fixing fundamentals first. |

---

## Definition of Done

- [ ] All Phase 1–4 tests passing
- [ ] `SOLID_QUEUE_IN_PUMA: false` deployed
- [ ] `docker ps` on production shows a separate jobs container
- [ ] No `[CacheInvalidator] Skipping invalidation` lines in production logs
- [ ] `kamal-proxy` running ≥ v0.9.2
- [ ] 2 GB swap active on `68.183.173.51` (`free -h` shows non-zero swap, `/etc/fstab` updated)
- [ ] Solid Queue queues unpaused
- [ ] Backlog drained (or deleted and re-enqueued as batch jobs)
- [ ] Site responsive, web container memory stable for ≥ 10 min after unpause
- [ ] `lib/specs/db_resilience_spec.md` Phase 4A updated to "superseded by `job_isolation_and_invalidation_fix_spec.md`"
- [ ] Spec moved to `lib/specs/old/`
- [ ] `lib/docs/BUSINESS_RULES.md` reviewed — no update needed (internal infrastructure change)

---

## Out of Scope

- **Droplet resize (2 GB → 4 GB)** — separate decision, swap covers the immediate risk.
- **DigitalOcean monitoring alerts** — config in DO dashboard, not in the repo.
- **Job timeout enforcement** (any job > 30 s gets killed) — needs design; deferred.
- **Health check based on queue depth** — deferred.
- **Multi-node / load balancer** — premature; revisit once the single node is provably stable for ≥ 30 days post-fix.
- **`db_resilience_spec.md` Phases 1–3** (error sanitisation, DB pool sizing, stuck-job cleanup) — separate, still valid, ship independently.
