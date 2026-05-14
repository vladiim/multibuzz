-- Drops TimescaleDB from template1 on fresh cluster initialisation.
--
-- Runs in /docker-entrypoint-initdb.d/ AFTER the timescale image's
-- 001_add_timescaledb.sh (which installs the extension into template1
-- per https://github.com/timescale/timescaledb-docker/pull/24/files)
-- and BEFORE our setup.sql (alphabetical order: 001_* < aaa-* < setup.sql).
--
-- This means any CREATE DATABASE statements in setup.sql produce databases
-- that do NOT inherit the timescaledb extension. The main app database
-- (multibuzz_production / $POSTGRES_DB) is created before initdb.d runs,
-- so it still has the extension installed by the image's own script.
--
-- No-op against an existing data volume; only runs when initdb.d fires
-- on a fresh PGDATA. See lib/specs/timescaledb_telemetry_cleanup_spec.md.

\c template1
DROP EXTENSION IF EXISTS timescaledb;
