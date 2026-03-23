# frozen_string_literal: true

module AdPlatformConnection::AdSpend
  extend ActiveSupport::Concern

  def spend_date_range
    ad_spend_records.pick(Arel.sql("MIN(spend_date)"), Arel.sql("MAX(spend_date)"))
  end

  def spend_records_count
    ad_spend_records.count
  end

  def recent_sync_runs(limit = 10)
    ad_spend_sync_runs.order(created_at: :desc).limit(limit)
  end

  SETTING_VERIFICATION_DISMISSED = "verification_dismissed"

  def verification_data
    yesterday_records.exists? ? yesterday_summary : nil
  end

  def verification_dismissed?
    settings&.dig(SETTING_VERIFICATION_DISMISSED) == true
  end

  private

  def yesterday_records
    @yesterday_records ||= ad_spend_records.where(spend_date: Date.yesterday)
  end

  def yesterday_summary
    {
      spend_micros: yesterday_records.sum(:spend_micros),
      campaign_count: yesterday_records.distinct.count(:platform_campaign_id)
    }
  end
end
