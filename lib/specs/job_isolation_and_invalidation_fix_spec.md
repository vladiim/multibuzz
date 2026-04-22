# Job Isolation & Cache-Invalidation Fix Specification

**Date:** 2026-04-22
**Priority:** P0
**Status:** Ready
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

Both call sites enqueue one job per conversion. Replace with one `BatchReattributionJob` per identity.

```ruby
# app/jobs/conversions/batch_reattribution_job.rb (new)
module Conversions
  class BatchReattributionJob < ApplicationJob
    queue_as :default

    def perform(identity_id)
      identity = Identity.find(identity_id)
      identity.conversions.find_each do |conversion|
        ReattributionService.new(conversion).call
      end
    end
  end
end
```

Update both call sites:

```ruby
# app/services/identities/identification_service.rb:66
Conversions::BatchReattributionJob.perform_later(identity.id)
# (instead of: conversions.each { ReattributionJob.perform_later(_1.id) })

# app/services/billing/unlock_events_service.rb:61
# Group by identity, enqueue one job per identity:
conversions.group_by(&:visitor_identity_id).each_key do |identity_id|
  Conversions::BatchReattributionJob.perform_later(identity_id) if identity_id
end
```

`Conversions::ReattributionJob` (the per-conversion job) stays — kept for explicit single-conversion reattribution and for the queued backlog. We do not remove it in this spec.

`find_each` keeps memory bounded. Per-conversion failure is contained (one bad conversion doesn't kill the batch — `ApplicationService` rescues internally).

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

### Phase 1 — Class-level cache-backend probe (TDD)

- [ ] **1.1** RED: Test `Dashboard::CacheInvalidator#call` returns nil and writes nothing when backend lacks `delete_matched` (use a stub backend that raises `NotImplementedError`)
- [ ] **1.2** RED: Test `Dashboard::CacheInvalidator#call` calls `Rails.cache.delete_matched` once per section when supported
- [ ] **1.3** RED: Test `DELETE_MATCHED_SUPPORTED` is computed once at class load (no per-call probe)
- [ ] **1.4** GREEN: Replace instance-memoised `supports_delete_matched?` with class-level `DELETE_MATCHED_SUPPORTED` constant
- [ ] **1.5** GREEN: Drop the per-call logger line; if you want to know the backend support, log it once at boot in an initializer (optional)
- [ ] **1.6** Full suite green

### Phase 2 — Batched invalidation in `ReattributionService` (TDD)

- [ ] **2.1** RED: Test `Conversions::ReattributionService#call` invokes `Dashboard::CacheInvalidator` exactly once per call (not per credit)
- [ ] **2.2** RED: Test `AttributionCredit#invalidate_dashboard_cache` is NOT fired for writes inside the service block
- [ ] **2.3** RED: Test other call sites of `AttributionCredit.create!` outside the service still fire the callback
- [ ] **2.4** GREEN: Wrap `delete_existing_credits` + `calculate_new_credits` in `AttributionCredit.skip_callback(:commit, :after, :invalidate_dashboard_cache) do ... end`
- [ ] **2.5** GREEN: Add explicit `Dashboard::CacheInvalidator.new(conversion.account).call` after the lock block on success
- [ ] **2.6** Full suite green

### Phase 3 — Coalesce fan-out (TDD)

- [ ] **3.1** RED: Test `Conversions::BatchReattributionJob#perform(identity_id)` calls `ReattributionService` once per conversion for the identity
- [ ] **3.2** RED: Test `Identities::IdentificationService` enqueues exactly one `BatchReattributionJob` per identity (not N `ReattributionJob`s)
- [ ] **3.3** RED: Test `Billing::UnlockEventsService` enqueues one `BatchReattributionJob` per distinct identity in the unlocked conversions
- [ ] **3.4** GREEN: Create `app/jobs/conversions/batch_reattribution_job.rb`
- [ ] **3.5** GREEN: Update `Identities::IdentificationService` enqueue site
- [ ] **3.6** GREEN: Update `Billing::UnlockEventsService` enqueue site
- [ ] **3.7** Full suite green

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

### Phase 5 — Operational recovery (sequential, on production)

- [ ] **5.1** `kamal proxy reboot` (verifies Phase 4 deploy will succeed)
- [ ] **5.2** Add 2 GB swap on `68.183.173.51`; persist via `/etc/fstab`
- [ ] **5.3** `kamal deploy` (ships Phases 1–4)
- [ ] **5.4** Verify: jobs container running (`docker ps | grep jobs`), web container responsive
- [ ] **5.5** Triage queued backlog (see Key Decisions): delete redundant `Conversions::ReattributionJob`s; keep one fresh `BatchReattributionJob` per affected identity
- [ ] **5.6** `SolidQueue::Pause.where(queue_name: %w[default low solid_queue_recurring]).destroy_all`
- [ ] **5.7** Watch logs and `docker stats` for 10 min; verify no CLOSE_WAIT growth, no memory drift, jobs draining

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
