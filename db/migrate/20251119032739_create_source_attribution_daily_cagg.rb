# frozen_string_literal: true

class CreateSourceAttributionDailyCagg < ActiveRecord::Migration[8.0]
  def up
    # Create continuous aggregate for traffic source breakdown by day
    # Aggregates sessions by UTM source/medium/campaign
    execute <<-SQL
      CREATE MATERIALIZED VIEW source_attribution_daily
      WITH (timescaledb.continuous) AS
      SELECT
        account_id,
        initial_utm->>'utm_source' AS utm_source,
        initial_utm->>'utm_medium' AS utm_medium,
        initial_utm->>'utm_campaign' AS utm_campaign,
        channel,
        time_bucket('1 day', started_at) AS day,
        COUNT(*) AS session_count,
        COUNT(DISTINCT visitor_id) AS unique_visitors,
        SUM(page_view_count) AS total_page_views
      FROM sessions
      WHERE initial_utm IS NOT NULL AND initial_utm != '{}'::jsonb
      GROUP BY account_id, utm_source, utm_medium, utm_campaign, channel, day
      WITH NO DATA;
    SQL

    # Add refresh policy: refresh last 7 days every hour
    execute <<-SQL
      SELECT add_continuous_aggregate_policy('source_attribution_daily',
        start_offset => INTERVAL '7 days',
        end_offset => INTERVAL '1 hour',
        schedule_interval => INTERVAL '1 hour');
    SQL
  end

  def down
    execute "SELECT remove_continuous_aggregate_policy('source_attribution_daily');"
    execute "DROP MATERIALIZED VIEW IF EXISTS source_attribution_daily;"
  end
end
