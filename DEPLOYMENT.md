# Multibuzz Deployment Guide

## Dependencies

### Database: PostgreSQL with TimescaleDB Extension

**Required for Production**:
- PostgreSQL 14+ (tested with PostgreSQL 18)
- TimescaleDB 2.23.1+

**Why**: Events and sessions tables use TimescaleDB hypertables for:
- 10-20x performance improvement for time-series queries
- Lossless compression (90% storage savings)
- Automatic time-based partitioning
- Continuous aggregates for instant dashboard queries

### Installation Options

#### Option 1: Timescale Cloud (Recommended for Production)
```bash
# Use managed TimescaleDB service
# https://www.timescale.com/cloud
# No server configuration needed
```

#### Option 2: AWS RDS with TimescaleDB
```bash
# RDS PostgreSQL with TimescaleDB extension
# https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts.timescaledb
```

#### Option 3: Self-hosted with Docker (Kamal)
```dockerfile
# Use TimescaleDB Docker image instead of plain PostgreSQL
# docker-compose.yml or Kamal accessory configuration

services:
  db:
    image: timescale/timescaledb:latest-pg18
    environment:
      POSTGRES_USER: multibuzz
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: multibuzz_production
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
```

#### Option 4: DigitalOcean Managed Database
```bash
# DigitalOcean PostgreSQL with TimescaleDB
# Enable TimescaleDB in database settings
```

### Kamal Configuration

Update `config/deploy.yml` to use TimescaleDB image:

```yaml
# config/deploy.yml

accessories:
  db:
    image: timescale/timescaledb:latest-pg18  # Use TimescaleDB image
    host: your-db-server.com
    port: 5432
    env:
      secret:
        - POSTGRES_PASSWORD
      clear:
        POSTGRES_USER: multibuzz
        POSTGRES_DB: multibuzz_production
    directories:
      - data:/var/lib/postgresql/data
    options:
      network: "multibuzz-network"
```

**Alternative**: If using external managed database (Timescale Cloud, AWS RDS, etc.):
- Don't configure `db` accessory in Kamal
- Set `DATABASE_URL` environment variable pointing to managed instance
- TimescaleDB extension already available

### Verification

After deployment, verify TimescaleDB is working:

```bash
# SSH into app container or connect to database
kamal app exec -i "bin/rails runner 'puts ActiveRecord::Base.connection.execute(\"SELECT extname FROM pg_extension WHERE extname = \\\"timescaledb\\\"\").first'"

# Should output: {"extname"=>"timescaledb"}
```

---

## Local Development Setup (macOS)

### Install PostgreSQL and TimescaleDB

```bash
# Install PostgreSQL via Homebrew
brew install postgresql@18
brew services start postgresql@18

# Install TimescaleDB
brew tap timescale/tap
brew install timescaledb

# Move TimescaleDB files to correct PostgreSQL version
timescaledb_move.sh

# Configure PostgreSQL for TimescaleDB (automatic tuning)
timescaledb-tune --quiet --yes

# Restart PostgreSQL
brew services restart postgresql@18
```

### Run Migrations

```bash
bin/rails db:create
bin/rails db:migrate
```

### Verify TimescaleDB

```bash
bin/rails runner "puts ActiveRecord::Base.connection.execute('SELECT extname FROM pg_extension WHERE extname = \'timescaledb\'').first"
# Output: {"extname"=>"timescaledb"}
```

---

## Production Checklist

- [ ] TimescaleDB extension available on PostgreSQL instance
- [ ] Database has sufficient resources (see tuning recommendations below)
- [ ] Continuous aggregates refreshing (automated by TimescaleDB)
- [ ] Compression policies active (check after 7 days for events, 30 days for sessions)
- [ ] Monitor chunk sizes and compression ratios
- [ ] Backup strategy includes hypertables (use `pg_dump` with TimescaleDB support)

### Resource Recommendations

**Minimum** (small-scale, < 1M events/month):
- 2 CPUs, 4GB RAM
- 20GB SSD storage

**Recommended** (medium-scale, 1-10M events/month):
- 4 CPUs, 8GB RAM
- 100GB SSD storage

**High-scale** (10M+ events/month):
- 8+ CPUs, 16GB+ RAM
- 500GB+ SSD storage
- Consider Timescale Cloud for automatic scaling

### TimescaleDB Tuning

Automatically tuned by `timescaledb-tune`, but key settings:
- `shared_preload_libraries = 'timescaledb'` (required)
- `shared_buffers` = 25% of RAM
- `effective_cache_size` = 75% of RAM
- `timescaledb.max_background_workers` = 16+
- `max_worker_processes` = 2x CPUs

---

## Monitoring

### Check Hypertable Status

```sql
-- Verify events and sessions are hypertables
SELECT * FROM timescaledb_information.hypertables
WHERE hypertable_name IN ('events', 'sessions');
```

### Check Compression Status

```sql
-- See compression stats
SELECT * FROM timescaledb_information.chunks
WHERE hypertable_name = 'events'
ORDER BY range_start DESC
LIMIT 10;

-- Check compression ratio
SELECT
  pg_size_pretty(before_compression_total_bytes) as before,
  pg_size_pretty(after_compression_total_bytes) as after,
  round((1 - after_compression_total_bytes::numeric / before_compression_total_bytes::numeric) * 100, 2) as compression_ratio
FROM timescaledb_information.hypertable_compression_stats
WHERE hypertable_name = 'events';
```

### Check Continuous Aggregates

```sql
-- Verify continuous aggregates exist and are refreshing
SELECT * FROM timescaledb_information.continuous_aggregates;

-- Check last refresh
SELECT * FROM timescaledb_information.job_stats
WHERE job_type = 'refresh_continuous_aggregate';
```

---

## Rollback Plan

If TimescaleDB causes issues, you can disable (but NOT RECOMMENDED after data exists):

```sql
-- WARNING: This will convert hypertables back to regular tables
-- Only do this if absolutely necessary and you understand the implications

-- Disable compression first
SELECT remove_compression_policy('events');
SELECT remove_compression_policy('sessions');

-- Drop continuous aggregates
DROP MATERIALIZED VIEW channel_attribution_daily;
DROP MATERIALIZED VIEW source_attribution_daily;
```

**Better approach**: Fix the issue rather than reverting. TimescaleDB is stable and production-ready.

---

## Support

- TimescaleDB Docs: https://docs.timescale.com/
- TimescaleDB Slack: https://timescaledb.slack.com/
- Kamal Docs: https://kamal-deploy.org/
