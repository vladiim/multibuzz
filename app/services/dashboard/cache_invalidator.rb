# frozen_string_literal: true

module Dashboard
  class CacheInvalidator
    SECTIONS = %w[conversions funnel].freeze

    def initialize(account)
      @account = account
    end

    def call
      return unless self.class.delete_matched_supported?
      SECTIONS.each { |section| Rails.cache.delete_matched(pattern_for(section)) }
    end

    # Class-level memoisation of an idempotent boolean. Concurrent computation
    # by multiple threads only ever writes the same value — no race-condition risk.
    # rubocop:disable ThreadSafety/ClassInstanceVariable
    def self.delete_matched_supported?
      return @delete_matched_supported if defined?(@delete_matched_supported)
      @delete_matched_supported = probe_delete_matched
    end

    def self.reset_delete_matched_support!
      remove_instance_variable(:@delete_matched_supported) if defined?(@delete_matched_supported)
    end
    # rubocop:enable ThreadSafety/ClassInstanceVariable

    def self.probe_delete_matched
      Rails.cache.delete_matched("__cache_invalidator_probe__")
      true
    rescue NotImplementedError
      false
    end
    private_class_method :probe_delete_matched

    private

    attr_reader :account

    def pattern_for(section) = "dashboard/#{section}/#{account.prefix_id}/*"
  end
end
