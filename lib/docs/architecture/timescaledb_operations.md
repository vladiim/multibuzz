# TimescaleDB Operations

**Updated:** 2026-05-12

Operational reference for TimescaleDB on mbuzz-db: which databases legitimately have the extension, how to verify the cluster is in the right shape, how the retention policy is configured, and what to do if telemetry growth comes back.

Background: 2026-05-11 disk-fill incident where `_timescaledb_internal.bgw_job_stat_history` reached ~9.6 GB in each of six databases, filling the 67 GB volume. See `lib/specs/timescaledb_telemetry_cleanup_spec.md` (or `lib/specs/old/` if archived) for the full remediation history.

---

## Cluster Topology

mbuzz-db runs a single Postgres 18 container (`timescale/timescaledb:2.23.1-pg18`) with the following databases:

| Database | Extension expected? | Why |
|---|---|---|
| `multibuzz_production` | **yes** | Main Rails app DB. `events` is intended to be a hypertable per `CLAUDE.md`. |
| `multibuzz_production_cache` | no | Solid Cache. No time-series data, no consumers of TimescaleDB. |
| `multibuzz_production_queue` | no | Solid Queue. Same reasoning. |
| `multibuzz_production_cable` | no | Solid Cable. Same reasoning. |
| `multibuzz_production_errors` | no | Solid Errors. Same reasoning. |
| `postgres` | no | Admin DB. Not used by the app. |
| `template1` | no | Postgres template. Must stay clean so future `CREATE DATABASE` does not inherit the extension. |
| `template0` | no | Pristine template (read-only). Untouched. |

If any non-`multibuzz_production` database shows `has_ext=t`, something has reinstalled the extension and Phase 2 of the cleanup spec needs to be re-run.

---

## Why Most DBs Do Not Have the Extension

The `timescale/timescaledb` Docker image installs `CREATE EXTENSION timescaledb` into `template1` during first-boot init ([timescale/timescaledb-docker PR #24](https://github.com/timescale/timescaledb-docker/pull/24/files)). Every subsequent `CREATE DATABASE` then inherits the extension. Each DB with the extension runs its own bgw_worker scheduler and writes to its own copy of `_timescaledb_internal.bgw_job_stat_history`, which has no effective retention out of the box.

Across six databases this added up to ~58 GB and killed the disk. The fix lives in two places:

- `config/postgres/initdb.d/aaa-drop-timescaledb-from-template1.sql` runs on fresh cluster init, before our `setup.sql` creates the Solid Stack DBs, so they no longer inherit.
- `db/production_setup.sql` no longer explicitly installs the extension in cache/queue/cable.

Both are mounted into the postgres accessory via `accessories.postgres.files:` in `config/deploy.yml`.

---

## Verifying Cluster Shape

Run from a workstation with Kamal access. All read-only.

### Per-DB extension check

```bash
for db in multibuzz_production_queue multibuzz_production_cable multibuzz_production_cache multibuzz_production_errors postgres template1; do
  echo "=== $db ==="
  bin/kamal accessory exec postgres --reuse "psql -U multibuzz -d $db -tAc \"SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='timescaledb');\""
done
```

Expected: `f` for every DB. Any `t` indicates the extension has crept back in.

### Main DB sanity check

```bash
bin/kamal accessory exec postgres --reuse "psql -U multibuzz -d multibuzz_production -tAc \"SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='timescaledb');\""
```

Expected: `t`.

### Scheduler process count

```bash
bin/kamal accessory exec postgres --reuse "psql -U multibuzz -d multibuzz_production -c \"SELECT count(*), string_agg(application_name, ', ') FROM pg_stat_activity WHERE backend_type LIKE '%TimescaleDB%';\""
```

Expected: `2` (one `TimescaleDB Background Worker Launcher`, one `TimescaleDB Background Worker Scheduler`). Anything higher means more than one DB has the extension.

---

## Version Pinning

Pinned to `timescale/timescaledb:2.23.1-pg18` in `config/deploy.yml`. Floating tags (`latest-pg18`) are banned because silent extension upgrades on a critical extension are how you wake up to a bad surprise.

Verify the running version:

```bash
bin/kamal accessory exec postgres --reuse "psql -U multibuzz -d multibuzz_production -tAc \"SELECT extversion FROM pg_extension WHERE extname='timescaledb';\""
```

To upgrade: bump the image tag in `config/deploy.yml`, deploy via Kamal, then run `ALTER EXTENSION timescaledb UPDATE;` on `multibuzz_production` and confirm the new version. Major version upgrades may require `pre-update.sql` / `post-update.sql` steps; check the TimescaleDB upgrade notes before bumping.

---

## Retention Policy

`_timescaledb_internal.bgw_job_stat_history` is bounded by TimescaleDB's built-in `policy_job_stat_history_retention` policy (job_id 3). Configured 2026-05-12 via `alter_job`:

```sql
SELECT alter_job(3,
  config => jsonb_build_object(
    'drop_after',             '7 days',
    'max_failures_per_job',   1000,
    'max_successes_per_job',  1000
  )
);
```

| Setting | Value | Meaning |
|---|---|---|
| `schedule_interval` | `06:00:00` | Runs every 6 hours. |
| `drop_after` | `7 days` | Discards rows older than 7 days. |
| `max_successes_per_job` | `1000` | Keeps at most 1000 success rows per source job. |
| `max_failures_per_job` | `1000` | Keeps at most 1000 failure rows per source job. |

Verify config:

```bash
bin/kamal accessory exec postgres --reuse "psql -U multibuzz -d multibuzz_production -c \"SELECT job_id, schedule_interval, config FROM timescaledb_information.jobs WHERE job_id = 3;\""
```

Verify the policy actually ran successfully:

```bash
bin/kamal accessory exec postgres --reuse "psql -U multibuzz -d multibuzz_production -xc \"SELECT job_id, last_run_started_at, last_successful_finish, last_run_status, total_runs, total_successes, total_failures FROM timescaledb_information.job_stats WHERE job_id = 3;\""
```

Healthy signs: `last_run_status = Success`, `last_successful_finish` recent (within the last 6 hours), failure-rate per recent runs near zero. If failures dominate, see "Debugging Unbounded Telemetry Growth" below.

**Expected size envelope:** `pg_total_relation_size('_timescaledb_internal.bgw_job_stat_history')` should stay under 100 MB sustained with these settings. Baseline post-cleanup (2026-05-12) was ~1.6 MB.

---

## Debugging Unbounded Telemetry Growth

If disk usage on mbuzz-db starts climbing again, check in this order.

### 1. Current telemetry table size

```bash
bin/kamal accessory exec postgres --reuse "psql -U multibuzz -d multibuzz_production -c \"SELECT pg_size_pretty(pg_total_relation_size('_timescaledb_internal.bgw_job_stat_history'));\""
```

Over 100 MB → something is wrong.

### 2. Did the extension leak back into another DB?

Run the per-DB extension check (above). If any non-`multibuzz_production` DB has `has_ext=t`, that DB is running its own scheduler and filling its own copy of the telemetry table. Drop it:

```sql
DROP EXTENSION timescaledb;  -- against the affected DB
```

Then check `template1` too. Future `CREATE DATABASE` inherits from `template1`.

### 3. Is the retention policy still healthy?

Re-run the job_stats query (above). If `last_run_status` is `Failed` or `total_failures` is climbing fast, the policy is being starved or erroring. Likely causes:

- **`max_worker_processes` exhaustion** ([TimescaleDB issue #8543](https://github.com/timescale/timescaledb/issues/8543)): when the worker pool is full, the scheduler logs a failure to the very table it is meant to prune. Feedback loop. Check:
  ```bash
  bin/kamal accessory exec postgres --reuse "psql -U multibuzz -d multibuzz_production -c \"SHOW max_worker_processes;\""
  ```
  Default is 8. If multiple DBs have the extension, each runs a scheduler. Single-DB setup (this cluster) should not hit the limit.
- **Policy missing or disabled.** Re-register if needed: see TimescaleDB docs on `add_retention_policy` / `policy_job_stat_history_retention`.

### 4. Recent improvements upstream

[TimescaleDB PR #8606](https://github.com/timescale/timescaledb/pull/8606) added `max_successes_per_job` / `max_failures_per_job` and changed the default schedule from monthly to daily. Our policy already uses these. If we upgrade past 2.23.1, re-check the defaults; if upstream changes the policy config shape, our `alter_job` call needs to be re-applied.

---

## Provisioning a Fresh Cluster

If mbuzz-db is rebuilt (DR, blue/green, new staging) the `initdb.d` scripts run on the fresh PGDATA. Both must be present:

| File | Path inside container | Purpose |
|---|---|---|
| `config/postgres/initdb.d/aaa-drop-timescaledb-from-template1.sql` | `/docker-entrypoint-initdb.d/aaa-drop-timescaledb-from-template1.sql` | Drops the extension from `template1` after the upstream image installs it. |
| `db/production_setup.sql` | `/docker-entrypoint-initdb.d/setup.sql` | Creates the Solid Stack DBs (which now inherit a clean `template1`). |

Both are mounted via the `accessories.postgres.files:` block in `config/deploy.yml`. Alphabetical ordering matters: `001_add_timescaledb.sh` (from the image) < `aaa-*.sql` (ours) < `setup.sql` (ours).

Post-init verification: run the per-DB extension check (above). Every non-`multibuzz_production` DB should print `f`.

If you ever need to verify locally before deploying a change to the init scripts:

```bash
docker run --rm -d \
  --name ts-verify \
  -e POSTGRES_USER=multibuzz \
  -e POSTGRES_PASSWORD=test \
  -e POSTGRES_DB=multibuzz_production \
  -v "$(pwd)/config/postgres/initdb.d/aaa-drop-timescaledb-from-template1.sql:/docker-entrypoint-initdb.d/aaa-drop-timescaledb-from-template1.sql:ro" \
  -v "$(pwd)/db/production_setup.sql:/docker-entrypoint-initdb.d/setup.sql:ro" \
  timescale/timescaledb:2.23.1-pg18 \
&& until docker exec ts-verify pg_isready -U multibuzz -d multibuzz_production >/dev/null 2>&1; do sleep 1; done \
&& sleep 2 \
&& for db in template1 multibuzz_production multibuzz_production_cache multibuzz_production_queue multibuzz_production_cable; do
  echo "=== $db ==="
  docker exec ts-verify psql -U multibuzz -d "$db" -tAc "SELECT extname FROM pg_extension WHERE extname='timescaledb';"
done \
; docker rm -f ts-verify >/dev/null
```

Only `multibuzz_production` should print `timescaledb`.

---

## `events` Hypertable Status

`CLAUDE.md` implies `events` should be a TimescaleDB hypertable. As of 2026-05-12, `multibuzz_production` has the extension installed but zero hypertables:

```bash
bin/kamal accessory exec postgres --reuse "psql -U multibuzz -d multibuzz_production -c \"SELECT count(*) FROM timescaledb_information.hypertables;\""
```

The hypertable migration either never ran or was rolled back. The extension stays installed because the migration is expected, and the retention policy described above belongs to TimescaleDB internals, not to any user hypertable. Converting `events` into a hypertable is its own spec; this doc is just operational state.

---

## References

- `lib/specs/timescaledb_telemetry_cleanup_spec.md` (or `lib/specs/old/`) — the remediation spec that landed this work
- `lib/specs/incidents/2026-04-22-puma-jam-reattribution-cache-flood.md` — different mechanism, similar shape (Puma starvation under DB pressure)
- `config/deploy.yml` — image pin and init-script mounts
- `config/postgres/initdb.d/aaa-drop-timescaledb-from-template1.sql` — fresh-init template1 fix
- `db/production_setup.sql` — Solid Stack DB creation
- [TimescaleDB issue #8543](https://github.com/timescale/timescaledb/issues/8543) — bgw telemetry growth under worker exhaustion
- [TimescaleDB PR #8606](https://github.com/timescale/timescaledb/pull/8606) — retention defaults tightened
- [timescale/timescaledb-docker PR #24](https://github.com/timescale/timescaledb-docker/pull/24/files) — root of the template1 inheritance behaviour
- [timescaledb_information.job_history docs](https://docs.timescale.com/api/latest/informational-views/job_history/) — view over `_timescaledb_internal.bgw_job_stat_history`
