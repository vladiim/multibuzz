# frozen_string_literal: true

module Billing
  class UsageCounter
    def initialize(account)
      @account = account
    end

    # --- Reading ---

    def current_usage
      Rails.cache.read(cache_key).to_i
    end

    def event_limit
      account.plan&.events_included || Billing::FREE_EVENT_LIMIT
    end

    def remaining_events
      [ event_limit - current_usage, 0 ].max
    end

    # --- Writing ---

    def increment!(count = 1)
      Rails.cache.increment(cache_key, count)
    end

    def reset!
      Rails.cache.delete(cache_key)
    end

    # --- Limit Checks ---

    def within_limit?
      current_usage < event_limit
    end

    def usage_percentage
      return 0 if event_limit.zero?

      [ (current_usage.to_f / event_limit * 100).round, 100 ].min
    end

    def approaching_limit?
      usage_percentage >= Billing::USAGE_WARNING_THRESHOLD
    end

    def at_limit?
      usage_percentage >= Billing::USAGE_LIMIT_THRESHOLD
    end

    private

    attr_reader :account

    def cache_key
      account.usage_cache_key
    end
  end
end
