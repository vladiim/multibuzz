# frozen_string_literal: true

class CreateChannelAttributionDailyCagg < ActiveRecord::Migration[8.0]
  def up
    # Create continuous aggregate for channel performance by day
    # Aggregates sessions by account, channel, and date
    # Automatically refreshes to keep dashboard queries fast (<100ms)
    execute <<-SQL
      CREATE MATERIALIZED VIEW channel_attribution_daily
      WITH (timescaledb.continuous) AS
      SELECT
        account_id,
        channel,
        time_bucket('1 day', started_at) AS day,
        COUNT(*) AS session_count,
        COUNT(DISTINCT visitor_id) AS unique_visitors,
        SUM(page_view_count) AS total_page_views,
        AVG(page_view_count) AS avg_page_views_per_session
      FROM sessions
      WHERE channel IS NOT NULL
      GROUP BY account_id, channel, day
      WITH NO DATA;
    SQL

    # Add refresh policy: refresh last 7 days every hour
    execute <<-SQL
      SELECT add_continuous_aggregate_policy('channel_attribution_daily',
        start_offset => INTERVAL '7 days',
        end_offset => INTERVAL '1 hour',
        schedule_interval => INTERVAL '1 hour');
    SQL
  end

  def down
    execute "SELECT remove_continuous_aggregate_policy('channel_attribution_daily');"
    execute "DROP MATERIALIZED VIEW IF EXISTS channel_attribution_daily;"
  end
end
