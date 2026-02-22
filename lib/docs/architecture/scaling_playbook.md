# mbuzz Scaling Playbook

> Proactive scaling triggers and action plans. Don't wait for the fire — act at the smoke.

### Principles

1. **No paid services until revenue justifies them.** Use free/built-in tools aggressively. Paid monitoring/APM at 20+ customers, not before.
2. **CI health checks over dashboards.** Automated tests that run in CI and flag scaling thresholds — we catch problems before they catch us.
3. **SolidErrors + log archival is our monitoring stack** until customer count warrants more.

## Current Infrastructure Baseline

| Component | Current State | Details |
|-----------|--------------|---------|
| App server | Single DO droplet | 68.183.173.51 |
| Database | Self-managed TimescaleDB (pg18) | Separate droplet 64.225.47.17, private network 10.120.0.3 |
| Puma | 3 threads, 2 workers | WEB_CONCURRENCY=2, SOLID_QUEUE_IN_PUMA=true |
| DB pool | 5 connections | Matches RAILS_MAX_THREADS |
| Backups | Daily pg_dump to DO Spaces | 3am UTC, 7-day retention, `s3://mbuzz/mbuzz/backups/daily/` |
| pg_stat_statements | Enabled | Tracking all queries, 1000 statement limit |
| Health checks | CI + daily recurring job | `bin/rails infra:health`, 5am UTC via SolidQueue |
| Slow query logger | Enabled | Logs queries >100ms via ActiveSupport notifications |
| Staging | **NONE** | |
| CDN | **NONE** | |
| Monitoring | Health checks + SolidErrors | /up, /api/v1/health, infra:health rake task |
| TimescaleDB | Compression enabled (7d), 1-week chunks | Continuous aggregates for attribution |
| Deploy | Kamal + Thruster + GHCR | jemalloc enabled |

---

## Phase 0: Foundation (Now — Pre-Customer)

**Do these immediately. They're free or near-free and prevent data loss.**

### 0.1 Database Backups — DONE

Daily pg_dump to DO Spaces via `docker exec` (avoids pg client version mismatch with PG18).

```bash
# /root/backup-mbuzz.sh (on DB droplet)
#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="/tmp/mbuzz_${TIMESTAMP}.dump"
S3_PATH="s3://mbuzz/mbuzz/backups/daily/"

docker exec multibuzz-postgres \
  pg_dump -U multibuzz -Fc multibuzz_production \
  > "$BACKUP_FILE"

s3cmd put "$BACKUP_FILE" "$S3_PATH"

# Retention: keep 7 daily
s3cmd ls "$S3_PATH" \
  | sort -r \
  | tail -n +8 \
  | awk '{print $4}' \
  | xargs -I {} s3cmd del {}

rm -f "$BACKUP_FILE"

echo "[$(date)] Backup complete: mbuzz_${TIMESTAMP}.dump"
```

```bash
# Cron (on the DB droplet)
0 3 * * * /root/backup-mbuzz.sh >> /var/log/mbuzz-backup.log 2>&1
```

**Cost:** ~$5/mo for DO Spaces (250GB included).

**Upgrade path:** Move to WAL-G continuous archiving when database exceeds 50GB (gives point-in-time recovery with ~minute RPO instead of 24h).

### 0.2 Cloudflare (Free Tier)

**Action: Put mbuzz.co behind Cloudflare today.**

What you get for $0:
- CDN for static assets (CSS/JS/images)
- DDoS protection
- Free SSL termination
- DNS with fast propagation
- Basic analytics (requests, bandwidth, threats blocked)
- Caching rules for SDK snippet serving

**Setup:**
1. Add site to Cloudflare, update nameservers at registrar
2. SSL/TLS mode: **Full (Strict)** (Kamal already handles SSL via Let's Encrypt)
3. Cache rules: cache `/assets/*` aggressively, bypass `/api/*`
4. Page rule: `mbuzz.co/api/*` → Cache Level: Bypass

### 0.3 CI Infrastructure Health Checks — DONE

Automated smoke detector implemented as `Infrastructure::HealthCheckService` with five checks, each deriving its name from the class and using centralized thresholds from `app/constants/infrastructure.rb`.

**Checks:**
- `database_size` — warn >10GB, critical >50GB
- `connection_usage` — warn >50%, critical >75%
- `queue_depth` — warn >200, critical >2000
- `compression_ratio` — warn <70%, critical <50%
- `long_running_queries` — warn >1 query >5s, critical >3 queries >30s

**Run:** `bin/rails infra:health` (CI or manual), plus daily at 5am UTC via `Infrastructure::HealthCheckJob` (SolidQueue recurring).

### 0.4 Puma Workers — DONE

`WEB_CONCURRENCY: 2` enabled in `config/deploy.yml`. 2 workers x 3 threads = 6 concurrent requests.

**Phase 0 total cost: ~$5/mo** (DO Spaces only; everything else is free/built-in).

**What you already have that's sufficient for now:**
- **SolidErrors** — catches unhandled exceptions, stored in your `errors` database, viewable in dashboard
- **Log archival to DO Spaces** — production logs preserved and searchable
- **Rails health check** (`/up`) — confirms app boots
- **API health check** (`/api/v1/health`) — confirms API layer works

---

## Phase 1: First Paying Customers (1-10 accounts)

**Trigger:** First customer signs up on a paid plan, or you're actively demoing to prospects.

### 1.1 Staging Environment

**Why now:** You can't push untested migrations or features when customers depend on the product. Staging catches breaking changes before they hit production.

**Action:**
```yaml
# Spin up a $12/mo DO droplet (2 vCPU, 2GB RAM)
# Add to Kamal config as a separate destination:

# config/deploy.staging.yml
service: multibuzz
image: vladiim/multibuzz

servers:
  web:
    - <staging-ip>

proxy:
  ssl: true
  hosts:
    - staging.mbuzz.co

env:
  clear:
    RAILS_ENV: production
    POSTGRES_USER: multibuzz
    POSTGRES_DB: multibuzz_staging
    DB_HOST: localhost  # DB on same droplet for staging
    SOLID_QUEUE_IN_PUMA: true
```

Deploy: `kamal deploy -d staging`

**Cost:** ~$12-18/mo.

### 1.2 Uptime Monitoring (Free)

**Action:** UptimeRobot (free tier — 50 monitors, 5-min intervals).

Monitor:
- `https://mbuzz.co/up` — app health
- `https://mbuzz.co/api/v1/health` — API health

Alert via: email (free) or Slack webhook (free).

### 1.3 Droplet Sizing

**Trigger:** When you see any of these on the app droplet:
- CPU sustained >60% for 5 minutes
- Memory >80%
- Swap usage >0

**Action:** Resize the droplet. DO supports live resize for CPU/RAM.

| Customer Count | Recommended Droplet | vCPU | RAM | Cost/mo |
|---------------|---------------------|------|-----|---------|
| 0-5 | Basic $24 | 2 | 4GB | $24 |
| 5-10 | General Purpose $48 | 2 | 8GB | $48 |
| 10-25 | General Purpose $96 | 4 | 16GB | $96 |

**For the DB droplet, RAM matters most** — PostgreSQL uses it for shared_buffers and OS page cache. A 4GB RAM DB droplet should set `shared_buffers = 1GB`, `effective_cache_size = 3GB`.

### 1.4 Slow Query Logging — DONE (moved to Phase 0)

`pg_stat_statements` enabled in production (`pg_stat_statements.max = 1000`, `pg_stat_statements.track = all`). Rails-side slow query logger active via `config/initializers/slow_query_logger.rb` (threshold: `Infrastructure::SLOW_QUERY_THRESHOLD_MS`, default 100ms).

### 1.5 Database Size Monitoring

**Action:** Weekly cron that logs database size and projects growth.

```sql
-- Run weekly, log results
SELECT
  hypertable_name,
  pg_size_pretty(hypertable_size(format('%I.%I', hypertable_schema, hypertable_name))) AS total_size,
  pg_size_pretty(pg_total_relation_size(format('%I.%I', hypertable_schema, hypertable_name))) AS table_size,
  num_chunks,
  compression_enabled
FROM timescaledb_information.hypertables;
```

**Alert when:**
- Total DB size >50% of disk: plan disk expansion
- Total DB size >70% of disk: expand disk immediately
- Growth rate projects disk full in <30 days: expand disk immediately

---

## Phase 2: Growth (10-50 accounts, ~$5-20K MRR)

### 2.1 Separate SolidQueue from Puma

**Trigger:** Any of these:
- Job queue depth regularly >100
- Event ingestion latency >2 seconds
- Puma request queue time >50ms (jobs competing with web requests for resources)

**Action:** Stop running SolidQueue inside Puma. Deploy a dedicated worker process.

```yaml
# config/deploy.yml
env:
  clear:
    # Remove: SOLID_QUEUE_IN_PUMA: true
    SOLID_QUEUE_IN_PUMA: false

servers:
  web:
    - 68.183.173.51
  job:
    hosts:
      - 68.183.173.51  # same server initially, separate process
    cmd: bundle exec rake solid_queue:start
```

If the single droplet can't handle both web + worker, add a dedicated worker droplet ($24/mo).

### 2.2 Connection Pooling (PgBouncer)

**Trigger:** Any of these:
- Active connections >50% of `max_connections`
- `ActiveRecord::ConnectionTimeoutError` in logs
- Adding a second app server or separate worker server

**Action:** Add PgBouncer as a Kamal accessory.

```yaml
# config/deploy.yml
accessories:
  pgbouncer:
    image: edoburu/pgbouncer:latest
    host: 64.225.47.17  # on DB droplet
    port: "10.120.0.3:6432:6432"
    env:
      clear:
        POOL_MODE: transaction
        MAX_CLIENT_CONN: 200
        DEFAULT_POOL_SIZE: 20
        RESERVE_POOL_SIZE: 5
      secret:
        - DATABASE_URL
```

Update `DB_PORT` to `6432`. Add `prepared_statements: false` to `database.yml` production config (required for transaction pooling mode).

### 2.3 Read Replica

**Trigger:**
- Dashboard queries causing >100ms latency on API ingestion endpoints
- DB CPU sustained >60%
- Users complaining dashboard is slow

**Action:** Set up PostgreSQL streaming replication to a second DB droplet.

```yaml
# config/database.yml
production:
  primary:
    <<: *default
    host: <%= ENV["DB_HOST"] %>
  primary_replica:
    <<: *default
    host: <%= ENV["DB_REPLICA_HOST"] %>
    replica: true
```

```ruby
# In dashboard controllers/services
ActiveRecord::Base.connected_to(role: :reading) do
  DashboardQuery.new(current_account).call
end
```

**Cost:** Another DB droplet (~$48-96/mo depending on size). TimescaleDB continuous aggregates and compressed chunks replicate normally via streaming replication.

### 2.4 Error Tracking Upgrade (20+ customers)

**Trigger:** SolidErrors dashboard isn't cutting it — you need real-time alerts when errors spike, not manual checking.

**Action:** Add Honeybadger ($26/mo) or Sentry (free tier up to 5K errors/mo). These add: Slack/email alerts on new errors, error grouping/deduplication, deploy tracking, and trend detection. Until then, SolidErrors is sufficient.

### 2.5 Retention Policies

**Trigger:** Database exceeds 20GB, or you want to control storage costs proactively.

**Action:** Add retention policies for raw event data.

```sql
-- Drop raw events older than 90 days (continuous aggregates retain the summaries)
SELECT add_retention_policy('events', INTERVAL '90 days');

-- Sessions: keep 180 days (attribution lookback window)
SELECT add_retention_policy('sessions', INTERVAL '180 days');

-- api_request_logs: keep 30 days
-- (if this table grows — it logs every API call)
```

Before enabling retention, ensure your continuous aggregates cover the analytics queries that need historical data. The daily aggregates you already have (`source_attribution_daily`, `channel_attribution_daily`) are a good start.

**Consider adding:**
- Hourly event aggregates (for detailed recent analysis)
- Conversion aggregates (conversions per day per channel — though conversions are low-volume and may not need aggregation)

### 2.6 Backup Upgrade: WAL-G

**Trigger:** Database exceeds 50GB, or 24-hour RPO from daily pg_dump is no longer acceptable.

**Action:** Replace daily pg_dump with WAL-G continuous archiving.

WAL-G archives every WAL segment to DO Spaces as it's written, giving you point-in-time recovery to any moment in time. RPO drops from 24 hours to minutes.

```bash
# Install WAL-G on DB droplet
# Configure in postgresql.conf:
archive_mode = on
archive_command = 'wal-g wal-push %p'
archive_timeout = 60

# Full base backup weekly
0 2 * * 0 wal-g backup-push /var/lib/postgresql/data

# Retain 7 base backups
wal-g delete retain FULL 7 --confirm
```

**Keep the daily pg_dump as a secondary backup** — belt and suspenders.

---

## Phase 3: Scale (50-200 accounts, ~$20-100K MRR)

### 3.1 Horizontal App Servers

**Trigger:**
- Single app server maxed even after vertical scaling (>70% CPU on largest practical droplet)
- Need zero-downtime deploys (rolling deploys require 2+ servers)
- Customer SLAs require high availability

**Action:**

```yaml
# config/deploy.yml
servers:
  web:
    hosts:
      - 68.183.173.51      # app-1
      - <new-droplet-ip>    # app-2
  job:
    hosts:
      - <worker-droplet-ip>
    cmd: bundle exec rake solid_queue:start

proxy:
  ssl: false  # SSL at load balancer now
  host: mbuzz.co
  app_port: 3000
```

Add a DO Load Balancer ($12/mo) in front of both app servers. Remove Let's Encrypt from Kamal (LB handles SSL termination).

Kamal 2 handles rolling deploys natively — it deploys to one server at a time, waiting for health checks before proceeding.

### 3.2 APM (Application Performance Monitoring)

**Trigger:** 50+ customers. You need visibility into request latency, N+1 queries, and slow endpoints across your customer base. The slow query logger and PgHero aren't enough — you need distributed tracing.

**Action:** AppSignal (from $29/mo) — built for Rails, includes error tracking (can replace Honeybadger at this point), N+1 detection, background job monitoring. One tool replaces several.

### 3.3 Managed Database (Timescale Cloud)

**Trigger:** Any of these:
- DBA tasks consuming >4 hours/week (backup testing, pg upgrades, replication management, performance tuning)
- Database exceeds 100GB
- Need HA with automatic failover
- SOC2 audit requires managed infrastructure documentation
- Revenue justifies the cost ($150-500/mo)

**Action:** Migrate to Timescale Cloud.

What you get:
- Automated backups with PITR
- High availability with automatic failover
- Monitoring and alerting built in
- Compression, continuous aggregates, all TimescaleDB features
- Tiered storage (auto-moves old data to S3 — massive cost savings)
- Read replicas on demand

**Migration path:**
1. `pg_dump` production DB
2. Create Timescale Cloud instance (same PG version)
3. `pg_restore` to Timescale Cloud
4. Re-create hypertables, compression policies, continuous aggregates
5. Update `DB_HOST` in deploy config to Timescale Cloud connection string
6. Cut over during low-traffic window

### 3.4 Geographic Considerations

**Trigger:**
- EU customers requiring GDPR data residency
- API ingestion latency >200ms from key markets
- Customer contracts specifying data location

**Don't trigger on:** Wanting to be "global" for its own sake. Single-region handles most analytics workloads just fine because event ingestion is fire-and-forget (clients don't wait for a response to render the page).

**If needed:** Deploy edge ingestion endpoints using Cloudflare Workers or Fly.io that buffer events and forward to the primary DB. This gives <50ms ingestion latency globally without multi-region database complexity.

### 3.5 CDN for SDK/Tracking Snippet

**Trigger:** When serving the JavaScript tracking snippet (if you add one for tag-manager-style integration).

**Action:** Serve SDK files from Cloudflare CDN or BunnyCDN. Every millisecond of SDK load time matters for data collection completeness.

---

## Phase 4: Enterprise Scale (200+ accounts, >$100K MRR)

At this point, hire someone to own infrastructure. But the roadmap:

| Milestone | Action |
|-----------|--------|
| >500GB database | Timescale Cloud tiered storage (auto-archive to S3) |
| >1TB database | Evaluate multi-node TimescaleDB or per-tenant database sharding |
| >$2K/mo infra spend | Evaluate AWS/GCP for volume discounts and managed services |
| Enterprise customers | SOC2, data residency, dedicated infrastructure options |
| Global customers | Multi-region ingestion endpoints, data residency compliance |
| >4 app servers | Kubernetes (DO Managed K8s or migrate to EKS) |

---

## Data Volume Projections

### Per-Customer Storage (Pre-Compression)

| Customer Size | Monthly Sessions | Monthly Events | Monthly Storage |
|--------------|-----------------|----------------|-----------------|
| Small (e-commerce, <100K visitors) | 80-120K | 250-650K | 180-400 MB |
| Medium (SaaS, 100K-1M visitors) | 500K-1.5M | 2.5-10M | 1.5-5 GB |
| Large (high-traffic, >1M visitors) | 2-10M | 10-100M | 5-50 GB |

### Aggregate Growth Projections

| Accounts | Avg Monthly Growth (raw) | With Compression (90%) | With Retention (90d) |
|----------|------------------------|----------------------|---------------------|
| 5 small | 1-2 GB/mo | 100-200 MB/mo | Steady state: ~600 MB |
| 10 mixed | 5-10 GB/mo | 500 MB-1 GB/mo | Steady state: ~3 GB |
| 50 mixed | 50-100 GB/mo | 5-10 GB/mo | Steady state: ~30 GB |
| 100 mixed | 100-200 GB/mo | 10-20 GB/mo | Steady state: ~60 GB |

**Key insight:** With compression + retention policies already configured (you have both), storage growth is very manageable. Your events compression policy (7-day) achieves ~90-95% reduction on repetitive event data. Your steady-state storage at 50 customers would be roughly 30GB — easily handled by a single DB server.

### Disk Size Triggers

| DB Size (on disk) | Action |
|-------------------|--------|
| 10 GB | Add weekly size monitoring script |
| 25 GB | Verify compression ratios are healthy (>85%) |
| 50 GB | Upgrade to WAL-G backups; evaluate disk resize |
| 100 GB | Evaluate Timescale Cloud or read replica |
| 250 GB | Timescale Cloud with tiered storage |
| 500 GB | Dedicated DBA/infra attention needed |

---

## Monitoring Cheat Sheet

### Thresholds That Mean "Act Now"

| Metric | Warning (investigate) | Critical (act today) |
|--------|----------------------|---------------------|
| **App CPU** | >60% sustained 5 min | >80% sustained 1 min |
| **App Memory** | >75% | >85% |
| **Disk Usage** | >60% | >80% |
| **DB Connections** | >50% of max | >75% of max |
| **P95 API Latency** | >100ms | >300ms |
| **P95 Dashboard Latency** | >500ms | >2s |
| **SolidQueue Depth** | >200 jobs | >2000 jobs |
| **Job Latency** | >5s | >30s |
| **Error Rate (5xx)** | >0.1% | >1% |
| **DB Cache Hit Ratio** | <97% | <93% |
| **Long-Running Queries** | >5s | >30s |
| **Backup Age** | >25 hours | >48 hours |

### What to Check Weekly

```sql
-- Database size trend
SELECT pg_size_pretty(pg_database_size('mbuzz_production'));

-- Table sizes (top 10)
SELECT
  hypertable_name,
  pg_size_pretty(hypertable_size(format('public.%I', hypertable_name))) AS size,
  num_chunks
FROM timescaledb_information.hypertables
ORDER BY hypertable_size(format('public.%I', hypertable_name)) DESC;

-- Compression stats
SELECT * FROM hypertable_compression_stats('events');
SELECT * FROM hypertable_compression_stats('sessions');

-- Slow queries (if pg_stat_statements enabled)
SELECT calls, round(mean_exec_time::numeric, 2) AS avg_ms,
       round(max_exec_time::numeric, 2) AS max_ms,
       left(query, 80) AS query
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Connection count
SELECT count(*) FROM pg_stat_activity WHERE state = 'active';

-- Unused indexes (candidates for removal)
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
WHERE idx_scan = 0 AND indexname NOT LIKE '%unique%' AND indexname NOT LIKE '%pkey%'
ORDER BY pg_relation_size(indexrelid) DESC
LIMIT 10;
```

---

## Cost Roadmap

| Phase | Monthly Cost | What You're Running |
|-------|-------------|-------------------|
| **Phase 0** (now) | ~$20-30 | App droplet + DB droplet + DO Spaces backup. No paid services. |
| **Phase 1** (1-10 customers) | ~$55-80 | Bigger droplets + staging. Free uptime monitoring. |
| **Phase 2** (10-50 customers) | ~$200-400 | Separate workers + read replica. Error tracker at 20+ customers. |
| **Phase 3** (50-200 customers) | ~$700-1500 | Multi-server + LB + managed DB + APM |
| **Phase 4** (200+ customers) | ~$2000+ | Full managed stack, dedicated infra |

At every phase, infrastructure cost should be <5% of MRR. If it's higher, you're over-provisioning. If it's below 2%, check if you're under-provisioning.

---

## Priority Action Items

1. ~~**Set up database backups**~~ — DONE. Daily pg_dump to `s3://mbuzz/mbuzz/backups/daily/`, 7-day retention.
2. **Put mbuzz.co behind Cloudflare** — free CDN + DDoS + SSL (remaining Phase 0 item)
3. ~~**Enable Puma workers**~~ — DONE. `WEB_CONCURRENCY: 2`.
4. ~~**Build CI health check rake task**~~ — DONE. `bin/rails infra:health` + daily recurring job.
5. ~~**Enable `pg_stat_statements`**~~ — DONE. Tracking all queries.
6. ~~**Slow query logger**~~ — DONE. `config/initializers/slow_query_logger.rb`.

All free except $5/mo for DO Spaces. No paid services — SolidErrors + log archival covers error tracking for now.
