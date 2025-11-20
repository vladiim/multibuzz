-- Production database initialization script for Multibuzz
-- This script runs automatically when the TimescaleDB container first starts

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Create additional databases for Rails 8 Solid gems
CREATE DATABASE multibuzz_production_cache;
CREATE DATABASE multibuzz_production_queue;
CREATE DATABASE multibuzz_production_cable;

-- Connect to cache database and enable TimescaleDB (optional, but good for consistency)
\c multibuzz_production_cache
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Connect to queue database and enable TimescaleDB (optional)
\c multibuzz_production_queue
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Connect to cable database and enable TimescaleDB (optional)
\c multibuzz_production_cable
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Switch back to main database
\c multibuzz_production
