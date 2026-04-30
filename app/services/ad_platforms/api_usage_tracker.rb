# frozen_string_literal: true

module AdPlatforms
  # Global daily-operations counter for ad-platform API calls. One class, every
  # adapter increments it via `ApiUsageTracker.increment!(:platform_name)`.
  #
  # Why global, not per-platform: cross-cutting infrastructure should live in one
  # place so new adapters cost zero and no two trackers can drift apart. Limits
  # are data (the LIMITS hash), not class structure.
  #
  # Counter is platform-global per day — a single rollup across all connections
  # of a given platform. Per-ad-account or per-connection rate-limit tracking is
  # a follow-up; this class first solves billing visibility.
  class ApiUsageTracker
    LIMITS = {
      google_ads: 15_000,
      meta_ads: 200_000
    }.freeze

    DISPLAY_NAMES = {
      google_ads: "Google Ads",
      meta_ads: "Meta Ads"
    }.freeze

    WARNING_THRESHOLD = 80
    CACHE_KEY_PREFIX = "ad_platforms_api_ops"

    def self.increment!(platform, count = 1)
      Rails.cache.increment(cache_key_for(platform), count, expires_in: remaining_seconds_today)
    end

    def self.current_usage(platform)
      Rails.cache.read(cache_key_for(platform)).to_i
    end

    def self.daily_limit_for(platform)
      LIMITS.fetch(platform.to_sym)
    end

    def self.display_name_for(platform)
      DISPLAY_NAMES.fetch(platform.to_sym)
    end

    def self.tracked_platforms
      LIMITS.keys
    end

    def self.usage_percentage(platform)
      limit = daily_limit_for(platform)
      return 0 if limit.zero?

      [ (current_usage(platform).to_f / limit * 100).round, 100 ].min
    end

    def self.approaching_limit?(platform)
      usage_percentage(platform) >= WARNING_THRESHOLD
    end

    def self.remaining_operations(platform)
      [ daily_limit_for(platform) - current_usage(platform), 0 ].max
    end

    def self.cache_key_for(platform)
      "#{CACHE_KEY_PREFIX}/#{platform}/#{Date.current.iso8601}"
    end

    def self.remaining_seconds_today
      Time.current.end_of_day.to_i - Time.current.to_i
    end

    private_class_method :cache_key_for, :remaining_seconds_today
  end
end
