# frozen_string_literal: true

module AdPlatforms
  module Google
    class ApiUsageTracker
      DAILY_OPERATION_LIMIT = 15_000
      WARNING_THRESHOLD = 80

      CACHE_KEY_PREFIX = "google_ads_api_ops"

      def self.increment!(count = 1)
        Rails.cache.increment(cache_key, count, expires_in: remaining_seconds_today)
      end

      def self.current_usage
        Rails.cache.read(cache_key).to_i
      end

      def self.usage_percentage
        return 0 if DAILY_OPERATION_LIMIT.zero?

        [ (current_usage.to_f / DAILY_OPERATION_LIMIT * 100).round, 100 ].min
      end

      def self.approaching_limit?
        usage_percentage >= WARNING_THRESHOLD
      end

      def self.remaining_operations
        [ DAILY_OPERATION_LIMIT - current_usage, 0 ].max
      end

      def self.cache_key
        "#{CACHE_KEY_PREFIX}/#{Date.current.iso8601}"
      end

      def self.remaining_seconds_today
        Time.current.end_of_day.to_i - Time.current.to_i
      end

      private_class_method :cache_key, :remaining_seconds_today
    end
  end
end
