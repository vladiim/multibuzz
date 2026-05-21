---
name: project_2026_05_21_sessions_fingerprint_cpu_storm
description: 2026-05-21 mbuzz-db CPU spikes (95%) from missing index on sessions(account_id, device_fingerprint, created_at) held inside the session-creation advisory lock
metadata:
  type: project
---
Multiple DigitalOcean alerts on 2026-05-21 ("mbuzz-db CPU > 85% for 5m") triggered by an N+1-shaped contention in `Sessions::CreationService`. `pg_stat_statements` showed 60.98% of total DB time in `pg_advisory_xact_lock` and 28.87% in a single sessions lookup — the lock and the lookup are coupled: the lookup runs *inside* the lock (`creation_service.rb:73-80`), so a slow lookup serialises every concurrent session create for the same account.

The slow lookup is `recent_fingerprint_session` (`creation_service.rb:160-166`): `account.sessions.where(device_fingerprint: ?).where("created_at > ?", 30.seconds.ago).order(:created_at).first`. The only candidate index, `index_sessions_for_resolution (visitor_id, device_fingerprint, last_activity_at)`, leads with `visitor_id`. Postgres fell back to `index_sessions_on_account_id` and filtered ~1.2M tuples per call on account 2 (1.95M sessions, ~98% of the table). EXPLAIN: 942ms / 79k blocks read. After adding `index_sessions_on_account_fingerprint_created_at (account_id, device_fingerprint, created_at) WHERE device_fingerprint IS NOT NULL`: 0.185ms / 10 blocks.

**Status: SHIPPED.** Migration `20260521010000_add_index_on_sessions_account_fingerprint_created_at.rb`. Applied to prod manually with `CREATE INDEX CONCURRENTLY` (134 MB index) and the `schema_migrations` row inserted; the migration is a no-op when it later runs via Kamal deploy.

**How to apply:**
- Any time you touch session-creation hot paths, treat anything inside `with_session_lock` as held-exclusive per `(account_id, device_fingerprint)`. A query that's "fast enough" for one account can melt the DB for an account with millions of sessions. Account 2 holds ~98% of the sessions table; every plan analysis should be done with account 2 substituted into the bind, not a small dev account.
- Prod `sessions` is NOT a hypertable (verified 2026-05-21 via `timescaledb_information.hypertables`) — `CREATE INDEX CONCURRENTLY` works in prod. Dev IS a hypertable, so Rails `algorithm: :concurrently` fails locally. The repo convention is `safety_assured { add_index ... }` without concurrent; apply prod indexes out-of-band with `CONCURRENTLY` to avoid the table lock during the build.
- Open structural risk: the lookup does not need to be inside the advisory lock. The lock only needs to protect the insert/race-resolution path. Moving `find_canonical_by_fingerprint` outside `with_session_lock` would reduce the lock-hold time to the actual write window. Not done in this fix; worth a follow-up spec if contention reappears under load growth.
- See also [[project_2026_04_22_outage_remediation]] and [[project_batch_reattribution_worker_lockup]] — same family of pattern: a per-record hot-path query whose cost is invisible at small scale.
