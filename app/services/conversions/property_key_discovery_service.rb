# frozen_string_literal: true

module Conversions
  class PropertyKeyDiscoveryService < ApplicationService
    STALE_THRESHOLD = 90.days

    # Reserved keys that should not be discovered as custom properties
    # These are system-level properties, not user-defined dimensions
    RESERVED_KEYS = %w[url referrer].freeze

    def initialize(account)
      @account = account
    end

    private

    attr_reader :account

    def run
      upsert_discovered_keys
      prune_stale_keys

      success_result(discovered_count: discovered_keys.size)
    end

    def upsert_discovered_keys
      discovered_keys.each { |key| upsert_key(key) }
    end

    def upsert_key(key)
      record = account.conversion_property_keys.find_or_initialize_by(property_key: key)
      record.occurrences = key_occurrence_count(key)
      record.last_seen_at = Time.current
      record.save!
    end

    # Properties are stored FLAT at root level: { "location" => "Sydney", "plan" => "pro" }
    # NOT nested: { "properties" => { "location" => "Sydney" } }
    def discovered_keys
      @discovered_keys ||= account
        .conversions
        .where("properties IS NOT NULL AND properties != '{}'::jsonb")
        .pluck(Arel.sql("DISTINCT jsonb_object_keys(properties)"))
        .reject { |key| RESERVED_KEYS.include?(key) }
    end

    def key_occurrence_count(key)
      account.conversions.where("jsonb_exists(properties, ?)", key).count
    end

    def prune_stale_keys
      account
        .conversion_property_keys
        .where("last_seen_at < ?", STALE_THRESHOLD.ago)
        .destroy_all
    end
  end
end
