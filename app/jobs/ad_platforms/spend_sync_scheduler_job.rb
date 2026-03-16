# frozen_string_literal: true

module AdPlatforms
  class SpendSyncSchedulerJob < ApplicationJob
    queue_as :default

    USAGE_WARNING_CACHE_KEY = "google_ads_api_usage_warning_sent"

    def perform
      AdPlatformConnection.active_connections.find_each do |connection|
        SpendSyncJob.perform_later(connection.id)
      end

      send_usage_warning if should_warn?
    end

    private

    def should_warn?
      Google::ApiUsageTracker.approaching_limit? && !already_warned_today?
    end

    def already_warned_today?
      Rails.cache.exist?(USAGE_WARNING_CACHE_KEY)
    end

    def send_usage_warning
      AdPlatformMailer.api_usage_warning(
        operations_today: Google::ApiUsageTracker.current_usage,
        limit: Google::ApiUsageTracker::DAILY_OPERATION_LIMIT,
        percentage: Google::ApiUsageTracker.usage_percentage
      ).deliver_now

      Rails.cache.write(USAGE_WARNING_CACHE_KEY, true, expires_in: remaining_seconds_today)
    end

    def remaining_seconds_today
      Time.current.end_of_day.to_i - Time.current.to_i
    end
  end
end
