# frozen_string_literal: true

module Infrastructure
  # --- Database Size (bytes) ---
  DATABASE_SIZE_WARNING = 10.gigabytes
  DATABASE_SIZE_CRITICAL = 50.gigabytes

  # --- Connection Usage (% of max_connections) ---
  CONNECTION_USAGE_WARNING = 50
  CONNECTION_USAGE_CRITICAL = 75

  # --- SolidQueue Depth (pending jobs) ---
  QUEUE_DEPTH_WARNING = 200
  QUEUE_DEPTH_CRITICAL = 2_000

  # --- TimescaleDB Compression Ratio (%) ---
  # Lower is worse — below these thresholds means compression isn't effective
  COMPRESSION_RATIO_WARNING = 70
  COMPRESSION_RATIO_CRITICAL = 50

  # --- Long-Running Queries ---
  LONG_QUERY_WARNING_SECONDS = 5
  LONG_QUERY_CRITICAL_SECONDS = 30
  LONG_QUERY_WARNING_COUNT = 1
  LONG_QUERY_CRITICAL_COUNT = 3

  # --- Slow Query Logger (ms) ---
  SLOW_QUERY_THRESHOLD_MS = 100
end
