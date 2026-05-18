-- Production database initialization script for Multibuzz
-- This script runs automatically when the TimescaleDB container first starts

-- Allow headroom for deploy overlap (2 containers × 5 DBs × 5 pool × 2 workers)
ALTER SYSTEM SET max_connections = 200;

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create additional databases for Rails 8 Solid gems.
-- These DBs must NOT have the timescaledb extension installed — they hold
-- only Solid Queue/Cache/Cable data, have no hypertables, and an unused
-- extension per DB spawns a background-worker scheduler that fills
-- _timescaledb_internal.bgw_job_stat_history (see 2026-05-11 outage and
-- lib/specs/timescaledb_telemetry_cleanup_spec.md).
--
-- aaa-drop-timescaledb-from-template1.sql runs before this file and removes
-- the inherited extension from template1, so these CREATE DATABASE calls
-- produce clean databases.
CREATE DATABASE multibuzz_production_cache;
CREATE DATABASE multibuzz_production_queue;
CREATE DATABASE multibuzz_production_cable;
