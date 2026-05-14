# TimescaleDB Telemetry Cleanup Specification

**Date:** 2026-05-11 (approach refined 2026-05-12 after research)
**Priority:** P0
**Status:** In Progress — Phase 1 complete (emergency truncate); Phases 0, 2–6 pending
**Branch:** TBD (suggest `fix/timescaledb-telemetry-cleanup`)

---

## Summary

mbuzz-db filled to 99% disk (1.2 GB free of 67 GB) and triggered a DigitalOcean uptime alert for `https://mbuzz.co/up` (5016 ms latency from us_west, 2026-05-11 07:04 UTC). Root cause: TimescaleDB's `_timescaledb_internal.bgw_job_stat_history` had grown to ~9.6 GB **in each of six databases** on the Postgres instance, including five (`multibuzz_production_{queue,cable,cache,errors}` and `postgres`) that don't use any TimescaleDB feature. Manual `TRUNCATE` across all six recovered ~58 GB; disk dropped to 14%.

This spec prevents recurrence in four layers, ordered by durability:

1. **Infrastructure (Phase 0)** — bind-mount a `docker-entrypoint-initdb.d/` script that drops TimescaleDB from `template1` on fresh cluster init, so future DR rebuilds or new staging clusters do not reintroduce the bug at first boot.
2. **One-shot production cleanup (Phases 2–3)** — manual `DROP EXTENSION` against the five non-app databases and `template1` on the *existing* cluster.
3. **Ongoing maintenance (Phase 4)** — keep `bgw_job_stat_history` bounded on the one database (`multibuzz_production`) where the extension legitimately stays installed. Prefer TimescaleDB's built-in `policy_job_stat_history_retention`; fall back to a Solid Queue truncate job only if the built-in policy is absent or broken on the installed TimescaleDB version.
4. **Documentation (Phase 5)** — `lib/docs/architecture/timescaledb_operations.md` so the next operator knows how this cluster is supposed to be shaped, why most DBs do not have the extension, and how to debug bgw growth.

---

## Timeline

| Time (UTC) | Event |
|------------|-------|
| 07:04 | DigitalOcean uptime monitor: `/up` = 5016 ms in us_west region |
| 07:12 | Alert email received |
| 07:13 | `curl https://mbuzz.co/up` from operator workstation: 250–820 ms (degraded but not 5 s) |
| 07:14 | DO Insights: mbuzz-db sustained 80–110 MB/s disk I/O, CPU 30–75%, load 2–4; mbuzz-jobs ↔ mbuzz-db bandwidth shows ~10-minute sawtooth |
| 07:20 | `df -h` on mbuzz-db reveals `/dev/vda1` at 99% (1.2 GB of 67 GB free) |
| 07:25 | Drilled into `/root/multibuzz-postgres/data/18/docker/base/`: 52 GB across six DB OIDs; five at ~9.6 GB each |
| 07:30 | Identified `_timescaledb_internal.bgw_job_stat_history` = 9646 MB in `multibuzz_production` |
| 07:35 | `TRUNCATE _timescaledb_internal.bgw_job_stat_history` on `multibuzz_production` → disk 99% → 85% |
| 07:40 | Same `TRUNCATE` across `multibuzz_production_{queue,cable,cache,errors}` + `postgres` → disk → 14% |
| 07:45 | Verified zero hypertables in any database — TimescaleDB has no real consumers in production |

---

## Current State

### Postgres Instance Layout (mbuzz-db, public 64.225.47.17 / VPC 10.120.0.3)

Single Postgres 18 container (`timescale/timescaledb:latest-pg18`). PGDATA bind-mounted from host at `/root/multibuzz-postgres/data/18/docker/`. Container superuser is `multibuzz`; no `postgres` role exists.

### Databases On This Instance

| Database | Size (post-truncate) | Purpose | TimescaleDB legitimately required? |
|----------|---------------------|---------|------------------------------------|
| `multibuzz_production` | 3.2 GB | Main Rails app | **Yes** — `events` is intended to be a hypertable per `CLAUDE.md`, even though no hypertable exists in production today |
| `multibuzz_production_queue` | small | Solid Queue | No |
| `multibuzz_production_cable` | small | Solid Cable | No |
| `multibuzz_production_cache` | small | Solid Cache | No |
| `multibuzz_production_errors` | small | Solid Errors | No |
| `postgres` | small | Admin DB | No |
| `template1` | small | Template for new DBs | No |
| `template0` | small | Pristine template (read-only) | No |

### TimescaleDB Extension State (verified 2026-05-11 07:45 UTC, post-truncate)

| Database | Has Extension? | Hypertables | Continuous Aggregates |
|----------|---------------|-------------|----------------------|
| `multibuzz_production` | Yes | 0 | 0 |
| `multibuzz_production_queue` | Yes | 0 | 0 |
| `multibuzz_production_cable` | Yes | 0 | 0 |
| `multibuzz_production_cache` | Yes | 0 | 0 |
| `multibuzz_production_errors` | Yes | 0 | 0 |
| `postgres` | Yes | 0 | 0 |
| `template1` | Suspected yes (inheritance pattern requires it) | 0 | 0 |

---

## Root Cause

Two compounding sources, both fixable:

1. **Upstream Docker image inheritance.** The `timescale/timescaledb` image installs `CREATE EXTENSION timescaledb` into `template1` during first-boot init ([timescale/timescaledb-docker PR #24](https://github.com/timescale/timescaledb-docker/pull/24/files)). Every subsequent `CREATE DATABASE` inherits the extension. This explains why `multibuzz_production_errors` — which Rails auto-creates on first deploy — has it.

2. **Our own `db/production_setup.sql` (self-inflicted).** Discovered 2026-05-12 while rolling out the fix. Lines 11–25 of `db/production_setup.sql` (mounted at `/docker-entrypoint-initdb.d/setup.sql` via Kamal's `accessories.postgres.files:`) explicitly do `CREATE DATABASE multibuzz_production_{cache,queue,cable}` and then `CREATE EXTENSION IF NOT EXISTS timescaledb` in each. Even if template1 inheritance were neutralised, this script would still install the extension into three of the five non-app DBs. A comment in the file calls the extra installs `optional, but good for consistency` — that comment is the bug. The Solid Stack DBs hold no time-series data and have no consumers of TimescaleDB; there is no consistency to preserve.

Once installed, each DB with the extension runs an independent set of TimescaleDB background workers, and each writes to its own `_timescaledb_internal.bgw_job_stat_history` table. That table has no effective retention policy in our installation and grows without bound.

Over the lifetime of the deployment, six copies of the telemetry table grew to ~9.6 GB each (~58 GB total) on a 67 GB volume. Postgres needs disk headroom for WAL writes, autovacuum work files, and query temp files; at 99% full, autovacuum thrashes (the sustained 80–110 MB/s disk I/O visible in DO Insights), queries spill to a near-empty disk, and Puma threads stall on DB connection pool waits — which surfaces as `/up` latency.

The six independent bgw_worker scheduler processes (one per database with the extension) are also the most likely source of the **~10-minute sawtooth I/O pattern** visible in mbuzz-jobs ↔ mbuzz-db bandwidth — five of those schedulers are doing useful work for nobody.

---

## Why Not a Rails Migration?

The obvious "Rails-y" approach is `rails generate migration DropTimescaleDbExtension` per affected DB, using `db/queue_migrate/`, `db/cable_migrate/`, etc. We rejected this. Five reasons:

1. **Rails cannot reach the DBs that matter most.** `config/database.yml` declares connections for `primary`, `cache`, `queue`, `cable`, `errors` — four of the six affected DBs. The two it does **not** declare are `postgres` (admin DB) and `template1`. `template1` is the actual root cause, since the `timescale/timescaledb` Docker image installs the extension there on first boot and every `CREATE DATABASE` inherits it ([timescale/timescaledb-docker PR #24](https://github.com/timescale/timescaledb-docker/pull/24/files)). A migration would clean four of six DBs and leave the factory running.
2. **The extension was not installed by Rails.** It was installed by the Docker image's `initdb.d` scripts. A "drop extension" migration has no symmetric up-side in dev/CI (TimescaleDB is not even loaded there), so it cannot be a proper reversible migration. We would be using Rails' migration system to manage state that lives entirely outside Rails' control.
3. **Known Rails bug with extension lifecycle.** [rails/rails#29091](https://github.com/rails/rails/issues/29091) — down-migrating an extension cascades into deleting columns from *other* tables that depend on it. Even with `IF EXISTS` guards, mixing extension lifecycle with schema migrations is a known anti-pattern.
4. **In dev/CI the migration is a lying no-op.** TimescaleDB is never installed in `multibuzz_development_*` or `multibuzz_test_*` (per `CLAUDE.md`'s test-env guard rule). A `DROP EXTENSION IF EXISTS` migration runs there as a no-op — pure noise that obscures what migrations are supposed to mean.
5. **Solid Stack migration paths are fragile for ad-hoc work.** [rails/solid_queue#329](https://github.com/rails/solid_queue/issues/329) — `db:migrate` can clobber `queue_schema.rb`. The `db/queue_migrate/`, `db/cable_migrate/`, `db/cache_migrate/`, `db/errors_migrate/` directories exist for Solid's own schema migrations; adding one-shot extension operations to them increases surface area for accidents.

The cluster shape is infrastructure, not application schema. Treat it as infrastructure: fix `template1` at the Docker layer (Phase 0), clean the existing cluster once by hand (Phases 2–3), and let Rails handle only what is actually application logic — the ongoing telemetry cleanup on the one DB Rails owns (Phase 4).

---

## Proposed Solution

Four layers, ordered by durability:

1. **Layer 0 — Infrastructure root-cause fix (Phase 0).** Bind-mount a `zzz-drop-timescaledb-from-template1.sql` script into `/docker-entrypoint-initdb.d/` via `config/deploy.yml`. Postgres runs `initdb.d` scripts in alphabetical order on a fresh data directory, so `zzz-` ensures this runs after TimescaleDB's own init script and reverses the inheritance. This is a no-op on the *current* cluster (data dir already initialised) but guarantees that any future fresh init — DR rebuild, blue/green migration, new staging — does not reintroduce the bug.

2. **Layer 1 — One-shot production cleanup (Phases 2–3).** `DROP EXTENSION timescaledb` against the five non-app DBs (`multibuzz_production_queue`, `multibuzz_production_cable`, `multibuzz_production_cache`, `multibuzz_production_errors`, `postgres`) and against `template1`. No hypertables, no continuous aggregates, no other TS-owned objects exist in any of them, so `DROP EXTENSION` succeeds without `CASCADE`. Manual `docker exec ... psql` — not a Rails migration (see "Why Not a Rails Migration?" above).

3. **Layer 2 — Ongoing maintenance (Phase 4).** Investigate the built-in `policy_job_stat_history_retention` first — it is upstream's intended mechanism, runs inside TimescaleDB's bgw scheduler, and keeps the most recent N rows per job (useful debug info) rather than nuking everything. Newer TimescaleDB versions ship with `max_successes_per_job` and `max_failures_per_job` parameters and a daily schedule ([TimescaleDB PR #8606](https://github.com/timescale/timescaledb/pull/8606)). If the installed version has the policy and it is healthy, `alter_job` to tighten retention. Only fall back to the Solid Queue truncate job if the built-in is missing or broken.

4. **Layer 3 — Documentation (Phase 5).** New `lib/docs/architecture/timescaledb_operations.md` capturing the desired cluster shape, why most DBs do not have the extension, how to verify state, version-pinning policy, and bgw growth debugging. Without this, the next operator (or future-us) re-derives the entire investigation from scratch.

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `config/postgres/initdb.d/aaa-drop-timescaledb-from-template1.sql` | Postgres init hook | Create — runs `\c template1; DROP EXTENSION IF EXISTS timescaledb;` after TimescaleDB's own init and **before** our `setup.sql` (alphabetical ordering: `001_*` < `aaa-*` < `setup.sql`) |
| `db/production_setup.sql` | Existing Postgres init script | Edit — remove the three `\c multibuzz_production_{cache,queue,cable}` + `CREATE EXTENSION` blocks; keep the `CREATE DATABASE` lines and the single `CREATE EXTENSION` for `multibuzz_production` |
| `config/deploy.yml` | Kamal config | Add `files:` entry mounting the new init script into the postgres accessory at `/docker-entrypoint-initdb.d/aaa-drop-timescaledb-from-template1.sql`; pin TimescaleDB image to a specific version (replace `latest-pg18`) |
| `app/jobs/infrastructure/timescale_telemetry_cleanup_job.rb` | Thin job wrapper (fallback only) | Create if Phase 4a determines built-in policy unusable — `perform` delegates to service |
| `app/services/infrastructure/timescale_telemetry_cleanup.rb` | Cleanup service (fallback only) | Create if Phase 4a determines built-in policy unusable — runs `TRUNCATE _timescaledb_internal.bgw_job_stat_history` against the primary connection |
| `config/recurring.yml` | Solid Queue schedule (fallback only) | Add `timescale_telemetry_cleanup` entry at 4:30am daily, only if the Solid Queue path is chosen |
| `test/jobs/infrastructure/timescale_telemetry_cleanup_job_test.rb` | Job test (fallback only) | Create if applicable — verifies job delegates to service |
| `test/services/infrastructure/timescale_telemetry_cleanup_test.rb` | Service test (fallback only) | Create if applicable — covers happy path, idempotency when table absent, and test-env tolerance per `CLAUDE.md` TimescaleDB-in-tests rule |
| `lib/docs/architecture/timescaledb_operations.md` | Operations doc | Create — desired cluster shape, extension topology, version pinning, bgw growth debugging, retention policy verification |

Phases 0, 2, and 3 are operational/infrastructure tasks; they produce a small committed init script and a `deploy.yml` change but no Rails code.

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path | `bgw_job_stat_history` exists with rows | `TRUNCATE` succeeds, row count → 0, on-disk file shrinks immediately |
| Already empty | Table exists with no rows | `TRUNCATE` is a no-op, succeeds silently |
| Table missing | `_timescaledb_internal.bgw_job_stat_history` does not exist (extension absent — e.g. test env, or future state if TS is fully removed) | Service catches `ActiveRecord::StatementInvalid`, logs at `info`, returns success — job is idempotent |
| DB unreachable | Connection error mid-execution | Job retries per Solid Queue defaults; sustained failure surfaces via `Infrastructure::QueueDepthAlertJob` |
| Hypertable added later | A future hypertable is created in `multibuzz_production` | No impact — telemetry table is for bgw job stats, not hypertable data |

---

## Implementation Tasks

### Phase 0: Infrastructure Init Scripts (durable root-cause fix)

Prevents fresh cluster initialisation from reinstalling TimescaleDB into the wrong places. Two changes work together:

- A new init script that drops the extension from `template1` *before* `setup.sql` runs (so any DBs `setup.sql` creates do not inherit it).
- A surgical edit to `db/production_setup.sql` to remove the explicit `CREATE EXTENSION` blocks for the Solid Stack DBs.

Both changes are no-ops against the existing data directory (initdb.d only runs on a fresh volume); they protect all future cluster builds.

#### Init script ordering

Postgres runs files in `/docker-entrypoint-initdb.d/` in alphabetical order. The TimescaleDB image ships `001_add_timescaledb.sh`. Our existing mount is `setup.sql`. We want the new template1-drop script to run *after* the upstream install and *before* `setup.sql` creates the Solid Stack DBs (so they do not inherit). Naming it `aaa-drop-timescaledb-from-template1.sql` gives the correct order: `001_*` < `aaa-*` < `setup.sql`.

#### Tasks

- [ ] **0.1** Create `config/postgres/initdb.d/aaa-drop-timescaledb-from-template1.sql`:
  ```sql
  -- Runs in /docker-entrypoint-initdb.d/ AFTER timescale image's 001_add_timescaledb.sh
  -- and BEFORE our setup.sql (alphabetical: 001_* < aaa-* < setup.sql).
  -- Reverses template1 inheritance documented in:
  --   https://github.com/timescale/timescaledb-docker/pull/24/files
  -- so that any CREATE DATABASE statements in setup.sql produce DBs without timescaledb.
  \c template1
  DROP EXTENSION IF EXISTS timescaledb;
  ```
- [ ] **0.2** Edit `db/production_setup.sql` to remove the three `\c multibuzz_production_{cache,queue,cable}` blocks and their `CREATE EXTENSION` calls (lines 16–25 as of this spec). The extension legitimately stays only in `multibuzz_production` (the main DB context that line 8 already covers).
- [ ] **0.3** Update `config/deploy.yml` `accessories.postgres.files:` to also mount the new init script:
  ```yaml
  files:
    - db/production_setup.sql:/docker-entrypoint-initdb.d/setup.sql
    - config/postgres/initdb.d/aaa-drop-timescaledb-from-template1.sql:/docker-entrypoint-initdb.d/aaa-drop-timescaledb-from-template1.sql
  ```
- [ ] **0.4** Pin the TimescaleDB image in `config/deploy.yml` to a specific version tag (replace `latest-pg18`). Floating tags on critical extensions are how silent upgrades break things — verify the version against the one running on mbuzz-db today:
  ```sql
  SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';
  ```
  Then change `image: timescale/timescaledb:latest-pg18` → `image: timescale/timescaledb:<X.Y.Z>-pg18`.
- [ ] **0.5** Verify locally with a fresh volume:
  ```bash
  docker run --rm -d \
    -e POSTGRES_PASSWORD=test \
    -v "$(pwd)/db/production_setup.sql:/docker-entrypoint-initdb.d/setup.sql:ro" \
    -v "$(pwd)/config/postgres/initdb.d/aaa-drop-timescaledb-from-template1.sql:/docker-entrypoint-initdb.d/aaa-drop-timescaledb-from-template1.sql:ro" \
    --name ts-verify timescale/timescaledb:<X.Y.Z>-pg18
  # Wait ~10s for init to complete, then:
  docker exec ts-verify psql -U postgres -d template1 -c "\dx"             # expect: no timescaledb
  docker exec ts-verify psql -U postgres -d multibuzz_production -c "\dx"  # expect: timescaledb present
  docker exec ts-verify psql -U postgres -d multibuzz_production_cache -c "\dx"  # expect: no timescaledb
  docker exec ts-verify psql -U postgres -d multibuzz_production_queue -c "\dx"  # expect: no timescaledb
  docker exec ts-verify psql -U postgres -d multibuzz_production_cable -c "\dx"  # expect: no timescaledb
  docker rm -f ts-verify
  ```
- [ ] **0.6** Deploy via Kamal — the running cluster is unaffected (initdb.d scripts only run on a fresh data volume), but the changes are now in place for any future cluster rebuild.

### Phase 1: Emergency Truncate — COMPLETE (2026-05-11)

- [x] Truncate on `multibuzz_production`
- [x] Truncate on `multibuzz_production_queue`
- [x] Truncate on `multibuzz_production_cable`
- [x] Truncate on `multibuzz_production_cache`
- [x] Truncate on `multibuzz_production_errors`
- [x] Truncate on `postgres`
- [x] Verify disk < 30% (achieved 14%)
- [x] Verify `/up` latency back to baseline (250–370 ms from operator workstation)

### Phase 2: Drop Extension from Non-App Databases (manual, production)

For each database in `multibuzz_production_queue`, `multibuzz_production_cable`, `multibuzz_production_cache`, `multibuzz_production_errors`, `postgres`:

- [ ] **2.1** Re-verify zero hypertables and zero continuous aggregates:
  ```sql
  SELECT count(*) FROM timescaledb_information.hypertables;
  SELECT count(*) FROM timescaledb_information.continuous_aggregates;
  ```
- [ ] **2.2** Run `DROP EXTENSION timescaledb;` (no `CASCADE` — if anything depends, we want to know)
- [ ] **2.3** Verify with `\dx` — `timescaledb` row absent
- [ ] **2.4** After all five: confirm DB CPU baseline and 10-minute sawtooth I/O reduced in DO Insights

### Phase 3: Drop Extension from `template1` (manual, production)

- [ ] **3.1** Connect: `docker exec multibuzz-postgres psql -U multibuzz -d template1`
- [ ] **3.2** Run `DROP EXTENSION IF EXISTS timescaledb;`
- [ ] **3.3** Verify with `\dx` — extension absent from `template1`
- [ ] **3.4** Sanity check: `CREATE DATABASE _drop_me_test;` → connect → `\dx` → confirm new databases no longer inherit TimescaleDB → `DROP DATABASE _drop_me_test;`

### Phase 4: Ongoing Retention for `multibuzz_production`

The remaining database where TimescaleDB stays installed still needs `bgw_job_stat_history` bounded. Try the built-in mechanism before adding application code.

#### Phase 4a: Investigate built-in retention policy (no code yet)

- [ ] **4a.1** On `multibuzz_production`, capture:
  ```sql
  SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';
  SELECT job_id, application_name, schedule_interval, max_runtime, max_retries,
         next_start, scheduled, fixed_schedule, config
    FROM timescaledb_information.jobs
   WHERE proc_name = 'policy_job_stat_history_retention';
  SELECT job_id, last_run_status, last_finish, last_successful_finish, total_runs,
         total_successes, total_failures
    FROM timescaledb_information.job_stats
   WHERE job_id IN (SELECT job_id FROM timescaledb_information.jobs
                     WHERE proc_name = 'policy_job_stat_history_retention');
  ```
- [ ] **4a.2** Check for [issue #8543](https://github.com/timescale/timescaledb/issues/8543) symptoms — `max_worker_processes` exhaustion causing the retention job to fail and feed the very table it is meant to prune:
  ```sql
  SHOW max_worker_processes;
  SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'TimescaleDB Background Worker Launcher';
  ```
  Note: after Phase 2 reduces extension count from 6 DBs to 1, worker pressure drops significantly — `max_worker_processes` exhaustion is far less likely. Re-verify.
- [ ] **4a.3** Decide between paths and record the decision in this spec:
  - **Path A (preferred):** Built-in policy exists and is healthy → tighten it via `alter_job` to a daily schedule with low retention (`drop_after => '7 days'` or `max_successes_per_job => 100` if the parameter is available on the installed version per [TimescaleDB PR #8606](https://github.com/timescale/timescaledb/pull/8606)). Skip 4b. Document the `alter_job` command in `lib/docs/architecture/timescaledb_operations.md`.
  - **Path B (fallback):** Policy is missing, broken, or the installed version predates the modern retention parameters → proceed to 4b.

#### Phase 4b: Solid Queue truncate job (fallback only — skip if 4a chose Path A)

- [ ] **4b.1** Write `test/services/infrastructure/timescale_telemetry_cleanup_test.rb` (RED) — cover happy path, idempotency when table missing, test-env tolerance
- [ ] **4b.2** Create `Infrastructure::TimescaleTelemetryCleanup` service — executes raw `TRUNCATE` via `ApplicationRecord.connection`, rescues `ActiveRecord::StatementInvalid` for missing-table case
- [ ] **4b.3** Service tests GREEN
- [ ] **4b.4** Write `test/jobs/infrastructure/timescale_telemetry_cleanup_job_test.rb` (RED) — verifies job calls service
- [ ] **4b.5** Create `Infrastructure::TimescaleTelemetryCleanupJob` thin wrapper
- [ ] **4b.6** Job tests GREEN
- [ ] **4b.7** Register in `config/recurring.yml`:
  ```yaml
  timescale_telemetry_cleanup:
    class: Infrastructure::TimescaleTelemetryCleanupJob
    schedule: at 4:30am every day
  ```
- [ ] **4b.8** Full test suite passes (`bin/rails test`) — no regressions
- [ ] **4b.9** Deploy via Kamal

### Phase 5: Documentation — `lib/docs/architecture/timescaledb_operations.md`

Capture the desired cluster shape and operations playbook so the next operator does not re-derive this investigation. Modelled on `lib/docs/architecture/data_integrity_runbook.md` (concrete SQL, no fluff).

- [ ] **5.1** Create `lib/docs/architecture/timescaledb_operations.md` with these sections:
  - **Cluster topology** — table mapping each DB on mbuzz-db to whether TimescaleDB is expected to be present, with rationale
  - **Why most DBs do not have the extension** — pointer to this spec; one-paragraph summary of the template1 inheritance footgun
  - **Verifying cluster shape** — `\dx` per DB; `SELECT count(*) FROM timescaledb_information.hypertables;` per DB; expected output
  - **Version pinning** — currently pinned to `<version from Phase 0.3>`; how to verify and how to upgrade
  - **Retention policy** — chosen mechanism from Phase 4a (built-in policy with `alter_job` settings, or Solid Queue fallback); how to verify it ran; expected `bgw_job_stat_history` size envelope
  - **Debugging unbounded telemetry growth** — `pg_total_relation_size`, `pg_stat_activity` for bgw workers, `max_worker_processes` check, links to upstream issues ([#8543](https://github.com/timescale/timescaledb/issues/8543), [PR #8606](https://github.com/timescale/timescaledb/pull/8606))
  - **What to do if a fresh cluster is provisioned** — Phase 0 init script must be present; verification checklist for template1 hygiene
  - **`events` hypertable status** — currently zero hypertables in production despite `CLAUDE.md` implying `events` should be one; link to the future spec covering that migration
- [ ] **5.2** Link the new doc from `lib/docs/` index if one exists, and from `CLAUDE.md`'s TimescaleDB section as the operational reference.
- [ ] **5.3** Cross-reference: add a one-line pointer in this spec's References section back to the doc once written.

### Phase 6: Verification (1 week post-deploy)

- [ ] **6.1** `pg_total_relation_size('_timescaledb_internal.bgw_job_stat_history')` on `multibuzz_production` stays < 100 MB sustained
- [ ] **6.2** mbuzz-db disk usage < 30%
- [ ] **6.3** DO Insights 10-min sawtooth I/O pattern absent
- [ ] **6.4** Re-run Phase 0.4 verification against the *production* cluster's template1 (read-only check: `\c template1; \dx;` → no `timescaledb` row)
- [ ] **6.5** Spec updated with verification timestamp and moved to `lib/specs/old/`

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| Truncates the telemetry table | `test/services/infrastructure/timescale_telemetry_cleanup_test.rb` | After service runs, `_timescaledb_internal.bgw_job_stat_history` row count is 0 |
| Idempotent when table is missing | `test/services/infrastructure/timescale_telemetry_cleanup_test.rb` | When the extension/table is absent (default test env per `CLAUDE.md`), service does not raise and returns success |
| Job delegates to service | `test/jobs/infrastructure/timescale_telemetry_cleanup_job_test.rb` | Performing the job invokes the service |

Per `feedback_no_mocks.md`: no stubbing or mocking the truncate. The service runs against the real test database. If the extension is not present in the test database (the standard case per `CLAUDE.md`'s TimescaleDB-in-tests guard), the idempotency path is exercised naturally.

### Manual QA (Production)

1. **Post Phase 2/3:** `docker exec multibuzz-postgres psql -U multibuzz -d {db} -c "\dx"` for each non-app DB and `template1` → no `timescaledb` row.
2. **Post Phase 4 deploy:** Confirm `timescale_telemetry_cleanup` recurring job appears in `SolidQueue::RecurringTask` (or via the Solid Queue dashboard).
3. **+24h after Phase 4 deploy:** `SELECT count(*) FROM _timescaledb_internal.bgw_job_stat_history;` on `multibuzz_production` shortly after 04:30 UTC → 0 immediately, growing during the day.
4. **DO Insights, 1 week:** mbuzz-db sustained CPU baseline drops (from 30–50% to 10–20% expected); 10-min sawtooth bandwidth pattern absent.

---

## Definition of Done

- [ ] All Phase 0, 2, 3, 4, 5 tasks completed
- [ ] `bin/rails test` passes (only relevant if Phase 4b path was chosen)
- [ ] Production manual QA confirms extension removed from five DBs + `template1`
- [ ] Phase 0 init script verified locally against a fresh postgres volume
- [ ] TimescaleDB image tag pinned to a specific version in `config/deploy.yml`
- [ ] `lib/docs/architecture/timescaledb_operations.md` exists and is linked from `CLAUDE.md`
- [ ] mbuzz-db disk usage < 30% sustained for 7 days
- [ ] `/up` p95 latency < 500 ms across all DO uptime monitor regions for 7 days
- [ ] Spec moved to `lib/specs/old/`

---

## Out of Scope

- **`events` hypertable migration.** `CLAUDE.md` implies `events` should be a TimescaleDB hypertable but `timescaledb_information.hypertables` returns 0 rows in production — the migration either never ran or the hypertable was later dropped. Worth investigating in its own spec; does not block this remediation.
- **Resizing mbuzz-db droplet.** At 14% used / 58 GB free, no urgency.
- **Migrating PGDATA to a dedicated DO block volume.** Best practice (separates DB growth from droplet sizing, snapshottable independently), but not required to close this incident. Track as a follow-up infrastructure spec.
- **Adding a dedicated `bgw_job_stat_history` size metric.** Covered indirectly by mbuzz-db disk alerts.
- **TimescaleDB major version upgrade.** Newer TimescaleDB versions ship with stricter built-in retention defaults on this table. Worth doing eventually; not required here. Phase 0.3 only pins the *current* version — a deliberate upgrade is a separate change.

---

## References

### Internal
- DigitalOcean alert ID `847d0405-4fd4-4c2d-a73d-e9454f9d242f` (2026-05-11 07:04 UTC, us_west)
- `app/jobs/infrastructure/queue_cleanup_job.rb` — thin-job + service pattern Phase 4b would follow
- `app/services/infrastructure/queue_cleanup.rb` — matching service location
- `config/recurring.yml` — Solid Queue recurring registration
- `config/database.yml` — confirms Rails connects to `primary`/`cache`/`queue`/`cable`/`errors` only (not `postgres` or `template1`); the basis of "Why Not a Rails Migration?" reason #1
- `config/deploy.yml` — Kamal config touched in Phase 0
- `lib/docs/architecture/data_integrity_runbook.md` — style/structure reference for the new `timescaledb_operations.md` doc
- `CLAUDE.md` — TimescaleDB-in-tests guard, multi-tenancy and service-object conventions
- Related (different mechanism, similar shape — Puma starvation under DB pressure): `lib/specs/incidents/2026-04-22-puma-jam-reattribution-cache-flood.md`

### Upstream
- [timescale/timescaledb-docker PR #24](https://github.com/timescale/timescaledb-docker/pull/24/files) — the init script that installs TimescaleDB into `template1` on first boot (root cause of inheritance)
- [TimescaleDB issue #8543](https://github.com/timescale/timescaledb/issues/8543) — unbounded `bgw_job_stat_history` growth when `max_worker_processes` is exhausted (relevant to Phase 4a.2)
- [TimescaleDB PR #8606](https://github.com/timescale/timescaledb/pull/8606) — `max_successes_per_job` / `max_failures_per_job` parameters and daily schedule on the built-in retention policy (relevant to Phase 4a.3 Path A)
- [TimescaleDB docs — timescaledb_information.job_history](https://docs.timescale.com/api/latest/informational-views/job_history/) — the informational view over `_timescaledb_internal.bgw_job_stat_history`
- [rails/rails#29091](https://github.com/rails/rails/issues/29091) — `enable_extension` down-migration column cascade bug (cited in "Why Not a Rails Migration?" reason #3)
- [rails/solid_queue#329](https://github.com/rails/solid_queue/issues/329) — `db:migrate` clobbering `queue_schema.rb` (cited in reason #5)
- [PostgreSQL DROP EXTENSION docs](https://www.postgresql.org/docs/current/sql-dropextension.html)
