# frozen_string_literal: true

module AdPlatforms
  class SpendSyncSchedulerJob < ApplicationJob
    queue_as :default

    USAGE_WARNING_CACHE_KEY_PREFIX = "ad_platforms_api_usage_warning_sent"

    def perform
      AdPlatformConnection.active_connections.find_each do |connection|
        SpendSyncJob.perform_later(connection.id)
      end

      ApiUsageTracker.tracked_platforms.each do |platform|
        send_usage_warning(platform) if should_warn?(platform)
      end
    end

    private

    def should_warn?(platform)
      ApiUsageTracker.approaching_limit?(platform) && !already_warned_today?(platform)
    end

    def already_warned_today?(platform)
      Rails.cache.exist?(warning_cache_key(platform))
    end

    def send_usage_warning(platform)
      AdPlatformMailer.api_usage_warning(
        platform_name: ApiUsageTracker.display_name_for(platform),
        operations_today: ApiUsageTracker.current_usage(platform),
        limit: ApiUsageTracker.daily_limit_for(platform),
        percentage: ApiUsageTracker.usage_percentage(platform)
      ).deliver_now

      Rails.cache.write(warning_cache_key(platform), true, expires_in: remaining_seconds_today)
    end

    def warning_cache_key(platform)
      "#{USAGE_WARNING_CACHE_KEY_PREFIX}/#{platform}"
    end

    def remaining_seconds_today
      Time.current.end_of_day.to_i - Time.current.to_i
    end
  end
end
