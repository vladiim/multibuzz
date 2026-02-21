# frozen_string_literal: true

module Dashboard
  class CacheInvalidator
    SECTIONS = %w[conversions funnel].freeze

    def initialize(account)
      @account = account
    end

    def call
      SECTIONS.each { |section| invalidate_section(section) }
    end

    private

    attr_reader :account

    def invalidate_section(section)
      cache_pattern = "dashboard/#{section}/#{account.prefix_id}/*"

      if supports_delete_matched?
        Rails.cache.delete_matched(cache_pattern)
      else
        # SolidCache doesn't support delete_matched with wildcards.
        # Cache keys include dynamic MD5 hashes based on filter params,
        # so we can't predict them. Instead, we rely on the 5-minute TTL
        # to ensure data freshness. This is acceptable because:
        # 1. Dashboard data is not real-time critical
        # 2. TTL ensures max 5 min staleness
        # 3. Users can refresh to get latest data
        Rails.logger.info(
          "[CacheInvalidator] Skipping invalidation for #{section} " \
          "(cache store doesn't support delete_matched, relying on TTL)"
        )
      end
    end

    def supports_delete_matched?
      return @supports_delete_matched if defined?(@supports_delete_matched)

      @supports_delete_matched = begin
        # Test if delete_matched works without raising
        Rails.cache.delete_matched("__test_pattern_that_wont_match__")
        true
      rescue NotImplementedError
        false
      end
    end
  end
end
