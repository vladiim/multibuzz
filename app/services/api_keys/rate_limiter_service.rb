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
      return rate_limited_result if rate_limited?

      increment_counter
      allowed_result
    end

    private

    attr_reader :account, :limit, :window

    def rate_limited?
      current_count >= limit
    end

    def current_count
      @current_count ||= Rails.cache.read(cache_key) || 0
    end

    def increment_counter
      new_count = current_count + 1
      Rails.cache.write(cache_key, new_count, expires_in: window)
      @current_count = new_count
    end

    def cache_key
      @cache_key ||= "rate_limit:account:#{account.id}"
    end

    def remaining
      [limit - current_count, 0].max
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
