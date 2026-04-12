# Database Resilience & Connection Isolation

**Date:** 2026-04-13
**Priority:** P0
**Status:** Draft
**Branch:** `feature/session-bot-detection`

---

## Summary

The production site has crashed three times (March 5, March 21, April 12) with `DatabaseConnectionError: There is an issue connecting with your hostname: 10.120.0.3`. The root cause is that PostgreSQL's `max_connections` is set to **25** on a 2GB RAM droplet, but the app routinely holds **37+ connections** across 5 databases (primary, cache, queue, cable, errors). The app is already over capacity at idle — any spike (CSV export, dashboard query, session burst) pushes past the limit and PostgreSQL rejects new connections, taking the entire site down. Additionally, raw database errors (including the internal DB hostname) leak to customers via `ApplicationService`.

This spec addresses three layers: (1) never expose internal errors to users, (2) increase `max_connections` and right-size the DB to handle actual connection demand, (3) add guardrails so the app degrades gracefully under connection pressure.

---

## Current State

### Infrastructure

| Component | Config | Value |
|-----------|--------|-------|
| Server | Single droplet | 68.183.173.51 |
| Database | TimescaleDB on separate droplet | 64.225.47.17 (private: 10.120.0.3) |
| Puma workers | `WEB_CONCURRENCY` | 2 |
| Puma threads/worker | `RAILS_MAX_THREADS` | 3 (default) |
| SolidQueue | `SOLID_QUEUE_IN_PUMA` | true (runs inside Puma) |
| SolidQueue threads | `queue.yml` | 3 |
| SolidQueue processes | `JOB_CONCURRENCY` | 1 (default, commented out) |
| DB pool size | `database.yml` | 3 (inherits RAILS_MAX_THREADS) |
| Databases | 5 on one PG instance | primary, cache, queue, cable, errors |
| DB droplet RAM | 2GB | DigitalOcean droplet |
| PostgreSQL `max_connections` | **25** | TimescaleDB auto-configured for 2GB RAM |
| Statement timeout | not configured | none |
| Lock timeout | not configured | none |
| PgBouncer | not present | direct connections only |

### Connection math — the actual problem

```
Current idle connections (pg_stat_activity):
  multibuzz_production        9
  multibuzz_production_queue  8
  multibuzz_production_cable  5
  multibuzz_production_cache  4
  multibuzz_production_errors 1
  postgres (system)          10
  TOTAL:                     37

PostgreSQL max_connections:   25
```

**The app needs ~37 connections at idle. The DB allows 25.** PostgreSQL is already over capacity — it's surviving because some connections are idle and PG allows brief oversubscription, but any spike causes `DatabaseConnectionError` and the entire site goes down. This has happened three times in the last 5 weeks (March 5, March 21, April 12).

The 2GB TimescaleDB droplet auto-configures `max_connections=25` based on available RAM (each connection reserves ~10MB of memory). The app's 5 databases × pool size 3 × 2 Puma workers + SolidQueue = 37+ connections required.

### Crash history (same error each time)

| Date | Error | Trigger |
|------|-------|---------|
| 2026-03-05 | `DatabaseConnectionError: hostname 10.120.0.3` | Unknown |
| 2026-03-21 | `DatabaseConnectionError: hostname 10.120.0.3` | Unknown |
| 2026-04-12 | `DatabaseConnectionError: hostname 10.120.0.3` | CSV export from conversions dashboard |

All three crashes have the same root cause: connection count exceeds `max_connections=25`.

### Missing protections

- `max_connections=25` is too low for actual connection demand (~37)
- No `statement_timeout` — queries run indefinitely, holding connections
- No `lock_timeout` — advisory locks block forever
- `ApplicationService` leaks raw exception messages (DB hostnames, SQL errors) to the UI

### Key files

| File | Role |
|------|------|
| `config/deploy.yml:43` | `SOLID_QUEUE_IN_PUMA: true` |
| `config/database.yml:20` | Pool size (3, from RAILS_MAX_THREADS) |
| `config/queue.yml` | SolidQueue worker/thread config |
| `config/puma.rb:39` | SolidQueue plugin in Puma |
| `app/services/application_service.rb:12-14` | Raw error leaking to UI |
| `app/views/dashboard/conversions/show.html.erb:63` | Error rendering |
| `app/services/conversions/reattribution_service.rb` | Heavy reattribution with advisory locks |
| `app/services/attribution/markov/conversion_paths_query.rb` | Unbounded Markov query |

---

## Proposed Solution

Three phases, ordered by blast radius.

### Phase 1: Stop leaking errors (deploy immediately)

**1A. Sanitize `ApplicationService` error messages**

The `StandardError` catch-all currently passes `e.message` to the UI, which can include DB hostnames, SQL fragments, and stack traces.

```ruby
# BEFORE
rescue StandardError => e
  report_error(e)
  error_result([ "Internal error: #{e.message}" ])

# AFTER
rescue StandardError => e
  report_error(e)
  error_result([ "Something went wrong. Please try again shortly." ])
```

The error is still reported to SolidErrors via `report_error(e)` for debugging. Only the user-facing message changes.

**1B. Fix `CheckoutCompleted` plan-not-found**

`Billing::Handlers::CheckoutCompleted` raises `PlanNotFoundError < StandardError` to signal a missing plan. After 1A, the raise would be caught by the generic handler and lose the specific message. Convert to `error_result` instead of raising:

```ruby
# BEFORE
def validate_plan!
  return if plan.present?
  raise PlanNotFoundError, "Plan not found for slug: #{plan_slug.inspect}"
end

# AFTER
def handle_event
  return plan_not_found_error unless plan.present?
  activate_subscription
end

def plan_not_found_error
  error_result(["Plan not found for slug: #{plan_slug.inspect}"])
end
```

### Phase 2: Upgrade DB droplet and increase `max_connections`

**This is the primary fix.** The 2GB droplet auto-configures `max_connections=25`, but the app needs ~37 at idle and more under load.

**2A. Upgrade DB droplet from 2GB to 4GB RAM**

DigitalOcean droplet resize (64.225.47.17). TimescaleDB will auto-configure `max_connections` higher for 4GB (~50-60). If it doesn't auto-adjust, set it manually in `postgresql.conf`:

```
max_connections = 75
```

75 gives comfortable headroom: 37 idle + room for spikes (CSV exports, concurrent dashboard loads, session bursts) + 10 for PG system processes.

**2B. Add statement and lock timeouts**

Add to `config/database.yml` production config. This kills runaway queries before they hold connections indefinitely:

```yaml
production:
  primary: &primary_production
    <<: *default
    variables:
      statement_timeout: 30000   # 30 seconds
      lock_timeout: 10000        # 10 seconds
```

**2C. Increase connection pool to match actual thread count**

The pool is currently 3 (from `RAILS_MAX_THREADS`), but Puma + SolidQueue together need more. Set pool explicitly:

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_DB_POOL") { ENV.fetch("RAILS_MAX_THREADS") { 5 } } %>
```

Set `RAILS_DB_POOL=10` in `deploy.yml`.

### Phase 3: Prevent stuck job accumulation

The root cause of the recurring crashes is 992 stuck jobs retrying in an infinite loop, each retry burning a DB connection. Three fixes:

**3A. Discard on permanent failures**

DB connection errors and record-not-found won't resolve by retrying 3 seconds later. Discard immediately.

```ruby
# app/jobs/application_job.rb
class ApplicationJob < ActiveJob::Base
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError
  discard_on ActiveRecord::DatabaseConnectionError
  discard_on ActiveRecord::ConnectionNotEstablished
end
```

**3B. Prevent duplicate job enqueuing**

`SurveillanceSchedulerJob` runs every hour and blindly enqueues new jobs per account without checking if previous ones are stuck. This is how 625 accumulated. Add a guard:

```ruby
# app/jobs/data_integrity/surveillance_scheduler_job.rb
def perform
  Account.active.find_each do |account|
    next if job_already_queued?(account.id)
    SurveillanceJob.perform_later(account.id)
  end
end

def job_already_queued?(account_id)
  SolidQueue::Job
    .where(class_name: "DataIntegrity::SurveillanceJob", finished_at: nil)
    .where("arguments::text LIKE ?", "%[#{account_id}]%")
    .exists?
end
```

**3C. Nightly stuck job cleanup + alerting**

Add a recurring job that purges stale unfinished jobs and reports to SolidErrors when the count is concerning.

```ruby
# app/jobs/infrastructure/queue_cleanup_job.rb
class Infrastructure::QueueCleanupJob < ApplicationJob
  STALE_THRESHOLD = 24.hours
  ALERT_THRESHOLD = 50

  def perform
    stale = SolidQueue::Job.where(finished_at: nil).where("created_at < ?", STALE_THRESHOLD.ago)
    count = stale.count

    if count > ALERT_THRESHOLD
      Rails.error.report(
        RuntimeError.new("#{count} stuck jobs detected, purging"),
        handled: true,
        context: { stuck_count: count, breakdown: stale.group(:class_name).count }
      )
    end

    stale.destroy_all if count > 0
    Rails.logger.info("[QueueCleanup] Purged #{count} stuck jobs") if count > 0
  end
end
```

Add to `config/recurring.yml`:

```yaml
queue_cleanup:
  class: Infrastructure::QueueCleanupJob
  schedule: at 2am every day
```

### Phase 4: Future resilience (as we grow)

**4A. Separate SolidQueue from Puma**

Not the root cause of the current crashes, but good practice as traffic grows. When SolidQueue runs inside Puma, job and web threads share the same connection pool. Separating them means each gets its own pool and crash domain.

**4B. Monitor connection count**

The app already has `Infrastructure::ConnectionUsage` — wire it into the health check that runs daily. Alert when connections exceed 70% of `max_connections`.

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Normal load | Web + light jobs | Both responsive, pool < 50% |
| Heavy job burst | 1000+ reattribution jobs | Jobs queue and process sequentially, web unaffected |
| DB connection exhausted | Pool fully checked out | Web returns "Something went wrong" (not raw DB error) |
| DB unreachable | Network/host failure | Web returns "Something went wrong", SolidErrors logs real error |
| Long-running query | Query exceeds 30s | PostgreSQL kills it, connection returned to pool |
| Advisory lock contention | Multiple jobs lock same conversion | Second job waits up to 10s (lock_timeout), then fails gracefully |
| CSV export during job burst | Export job queued behind heavy jobs | Export waits in queue, web still responsive |

---

## Implementation Phases

### Phase 1: Error sanitization (TDD, deploy immediately)

- [ ] **1.1** RED: Test `ApplicationService` returns generic message for `StandardError`
- [ ] **1.2** RED: Test `ApplicationService` still reports real error to `Rails.error`
- [ ] **1.3** RED: Test `CheckoutCompleted` returns `error_result` for missing plan (not raise)
- [ ] **1.4** GREEN: Sanitize `ApplicationService` catch-all message
- [ ] **1.5** GREEN: Convert `CheckoutCompleted` from raise to `error_result`
- [ ] **1.6** Run full test suite — no regressions

### Phase 2: Database guardrails (deploy same day)

- [ ] **2.1** Resize DB droplet from 2GB to 4GB, set `max_connections = 75`
- [ ] **2.2** Add `statement_timeout` and `lock_timeout` to production DB config
- [ ] **2.3** Set `RAILS_DB_POOL=10` in deploy.yml env
- [ ] **2.4** Deploy and verify connections via `pg_stat_activity`

### Phase 3: Prevent stuck job accumulation (TDD)

- [ ] **3.1** RED: Test `ApplicationJob` discards `DatabaseConnectionError`
- [ ] **3.2** RED: Test `SurveillanceSchedulerJob` skips accounts with queued jobs
- [ ] **3.3** RED: Test `QueueCleanupJob` purges stale jobs and alerts above threshold
- [ ] **3.4** GREEN: Add `discard_on` to `ApplicationJob`
- [ ] **3.5** GREEN: Add duplicate guard to `SurveillanceSchedulerJob`
- [ ] **3.6** GREEN: Create `Infrastructure::QueueCleanupJob`
- [ ] **3.7** Add `queue_cleanup` to `config/recurring.yml`
- [ ] **3.8** Run full test suite — no regressions

### Phase 4: Future resilience (defer)

- [ ] **4.1** Separate SolidQueue from Puma (own Kamal role)
- [ ] **4.2** Wire connection monitoring into daily health check

---

## Testing Strategy

### Unit Tests (Phase 1)

| Test | File | Verifies |
|------|------|----------|
| Generic error message for StandardError | `test/services/application_service_test.rb` | "Something went wrong" not raw exception |
| Real error still reported | same | `Rails.error.report` called with original exception |
| RecordInvalid still specific | same | Validation errors remain descriptive |
| RecordNotFound still specific | same | Not-found errors remain descriptive |
| CheckoutCompleted missing plan | `test/services/billing/handlers/checkout_completed_test.rb` | Returns error_result, not raises |
| Discard on DatabaseConnectionError | `test/jobs/application_job_test.rb` | Job discarded, not retried |
| Scheduler skips queued accounts | `test/jobs/data_integrity/surveillance_scheduler_job_test.rb` | No duplicate enqueue |
| Cleanup purges stale jobs | `test/jobs/infrastructure/queue_cleanup_job_test.rb` | Jobs older than 24h destroyed |
| Cleanup alerts above threshold | same | `Rails.error.report` called when count > 50 |
| Cleanup no-ops when queue healthy | same | No purge, no alert |

### Infrastructure Verification (Phase 2-3)

```ruby
# Verify statement_timeout is active
ActiveRecord::Base.connection.execute("SHOW statement_timeout").first
# → {"statement_timeout"=>"30s"}

# Verify pool size
ActiveRecord::Base.connection_pool.size
# → 10

# Verify SolidQueue running separately
SolidQueue::Process.all.map { |p| [p.kind, p.pid] }
# → Should show separate PIDs from Puma workers
```

---

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Upgrade DB to 4GB | `max_connections` goes from 25 to ~75 | The 2GB droplet can't support 37+ connections the app needs. This is the primary fix. |
| Generic error message | "Something went wrong. Please try again shortly." | Never leak infrastructure details. Real error goes to SolidErrors. |
| Statement timeout: 30s | Long enough for dashboard queries, short enough to prevent starvation | Dashboard p95 is ~2s. 30s gives 15x headroom. |
| Pool size: 10 | Covers 3 web threads + 3 job threads + 4 headroom | Matches actual concurrency without over-provisioning. |
| Not adding PgBouncer | Adds operational complexity, not needed at current scale | Revisit if we move to multiple web servers or need >100 connections. |
| SolidQueue separation (Phase 3) | Defer to next deploy cycle | Not the root cause of crashes. Good practice as we grow, not urgent. |

---

## Definition of Done

- [ ] No raw exception messages visible to users (test-covered)
- [ ] `statement_timeout` and `lock_timeout` configured in production
- [ ] DB pool sized to actual thread count
- [ ] SolidQueue running as separate process (not in Puma)
- [ ] Web requests serve normally during heavy job processing
- [ ] All tests pass
- [ ] Spec moved to `old/`
- [ ] `BUSINESS_RULES.md` reviewed — no update needed (internal infrastructure change)

---

## Out of Scope

- PgBouncer — not needed at current scale, adds operational complexity
- Read replicas — premature optimization
- DB hardware upgrade — connection management is the issue, not compute
- Markov query optimization — separate concern, tracked in existing attribution work
- Rate limiting on CSV exports — separate feature
