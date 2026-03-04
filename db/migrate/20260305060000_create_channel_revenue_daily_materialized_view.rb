# frozen_string_literal: true

class CreateChannelRevenueDailyMaterializedView < ActiveRecord::Migration[8.0]
  def up
    return if Rails.env.test?

    safety_assured do
      execute <<-SQL
        CREATE MATERIALIZED VIEW channel_revenue_daily AS
        SELECT
          ac.account_id,
          ac.attribution_model_id,
          ac.channel,
          DATE(c.converted_at) AS day,
          SUM(ac.revenue_credit) AS total_revenue_credit,
          COUNT(DISTINCT ac.conversion_id) AS conversion_count
        FROM attribution_credits ac
        JOIN conversions c ON c.id = ac.conversion_id
        WHERE ac.is_test = false
        GROUP BY ac.account_id, ac.attribution_model_id, ac.channel, DATE(c.converted_at);
      SQL

      execute <<-SQL
        CREATE UNIQUE INDEX idx_channel_revenue_daily_unique
        ON channel_revenue_daily (account_id, attribution_model_id, channel, day);
      SQL
    end
  end

  def down
    return if Rails.env.test?

    safety_assured do
      execute "DROP MATERIALIZED VIEW IF EXISTS channel_revenue_daily;"
    end
  end
end
