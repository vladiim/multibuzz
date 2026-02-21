# frozen_string_literal: true

module ApiKeys
  class RateLimiterService
    DEFAULT_LIMIT = 1000
    DEFAULT_WINDOW = 3600

    def initialize(account, limit: DEFAULT_LIMIT, window: DEFAULT_WINDOW)
      @account = account
      @limit = limit
      @window = window
    end

    def call
      # Atomic increment - ensures thread safety under concurrent load
      @current_count = atomic_increment

      return rate_limited_result if rate_limited?

      allowed_result
    end

    private

    attr_reader :account, :limit, :window

    def rate_limited?
      current_count > limit
    end

    def current_count
      @current_count ||= Rails.cache.read(cache_key).to_i
    end

    def atomic_increment
      # Rails.cache.increment is atomic and handles initialization
      # If key doesn't exist, it initializes to 0 then increments to 1
      count = Rails.cache.increment(cache_key, 1, expires_in: window)

      # Some cache stores return nil on first increment, handle gracefully
      return count if count

      # Fallback: write initial value and return it
      Rails.cache.write(cache_key, 1, expires_in: window)
      1
    end

    def cache_key
      @cache_key ||= "rate_limit:account:#{account.id}"
    end

    def remaining
      [ limit - current_count, 0 ].max
    end

    def reset_at
      @reset_at ||= Time.current + window
    end

    def retry_after
      window
    end

    def allowed_result
      {
        allowed: true,
        remaining: remaining,
        reset_at: reset_at
      }
    end

    def rate_limited_result
      {
        allowed: false,
        remaining: 0,
        reset_at: reset_at,
        retry_after: retry_after,
        error: "Rate limit exceeded"
      }
    end
  end
end
