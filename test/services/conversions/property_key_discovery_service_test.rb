# frozen_string_literal: true

require "test_helper"

module Conversions
  class PropertyKeyDiscoveryServiceTest < ActiveSupport::TestCase
    setup do
      # Clean up any existing data
      ConversionPropertyKey.delete_all
    end

    test "discovers property keys from conversions" do
      create_conversion_with_properties(plan: "pro", source: "api")
      create_conversion_with_properties(plan: "enterprise")

      result = service.call

      assert result[:success]
      assert_includes discovered_keys, "plan"
      assert_includes discovered_keys, "source"
    end

    test "counts occurrences for each property key" do
      create_conversion_with_properties(plan: "pro")
      create_conversion_with_properties(plan: "enterprise")
      create_conversion_with_properties(source: "api")

      service.call

      plan_key = account.conversion_property_keys.find_by(property_key: "plan")
      source_key = account.conversion_property_keys.find_by(property_key: "source")

      assert_equal 2, plan_key.occurrences
      assert_equal 1, source_key.occurrences
    end

    test "updates last_seen_at timestamp" do
      create_conversion_with_properties(plan: "pro")

      freeze_time do
        service.call

        key = account.conversion_property_keys.find_by(property_key: "plan")

        assert_equal Time.current, key.last_seen_at
      end
    end

    test "prunes stale keys older than 90 days" do
      # Create a stale key
      account.conversion_property_keys.create!(
        property_key: "stale_key",
        occurrences: 1,
        last_seen_at: 91.days.ago
      )

      # Create a fresh key
      account.conversion_property_keys.create!(
        property_key: "fresh_key",
        occurrences: 1,
        last_seen_at: 30.days.ago
      )

      service.call

      refute account.conversion_property_keys.exists?(property_key: "stale_key")
      assert account.conversion_property_keys.exists?(property_key: "fresh_key")
    end

    test "returns discovered count" do
      create_conversion_with_properties(plan: "pro", source: "api")

      result = service.call

      assert result[:success]
      assert_equal 2, result[:discovered_count]
    end

    test "handles empty properties gracefully" do
      create_conversion_with_properties({})

      result = service.call

      assert result[:success]
      assert_empty discovered_keys
    end

    test "upserts existing keys without duplicating" do
      create_conversion_with_properties(plan: "pro")
      service.call

      initial_count = account.conversion_property_keys.count

      create_conversion_with_properties(plan: "enterprise")
      service.call

      assert_equal initial_count, account.conversion_property_keys.count
    end

    test "excludes reserved keys like url and referrer from discovery" do
      # Real-world data has url, referrer at root alongside custom properties
      account.conversions.create!(
        visitor: visitor,
        conversion_type: "test",
        properties: {
          "url" => "https://example.com/checkout",
          "referrer" => "https://example.com/cart",
          "location" => "Sydney",
          "plan" => "pro"
        },
        converted_at: Time.current
      )

      service.call

      # Should discover custom properties but NOT url/referrer
      assert_includes discovered_keys, "location"
      assert_includes discovered_keys, "plan"
      refute_includes discovered_keys, "url"
      refute_includes discovered_keys, "referrer"
    end

    test "discovers keys from flat properties structure" do
      # Flat structure (target format)
      account.conversions.create!(
        visitor: visitor,
        conversion_type: "test",
        properties: { "location" => "Melbourne", "tier" => "gold" },
        converted_at: Time.current
      )

      result = service.call

      assert result[:success]
      assert_includes discovered_keys, "location"
      assert_includes discovered_keys, "tier"
    end

    private

    def service
      @service ||= PropertyKeyDiscoveryService.new(account)
    end

    def account
      @account ||= accounts(:one)
    end

    def visitor
      @visitor ||= visitors(:one)
    end

    def discovered_keys
      account.conversion_property_keys.reload.pluck(:property_key)
    end

    # Properties are stored FLAT at root level, not nested
    # { "plan" => "pro", "source" => "api" }
    # NOT: { "properties" => { "plan" => "pro" } }
    def create_conversion_with_properties(properties)
      account.conversions.create!(
        visitor: visitor,
        conversion_type: "test",
        properties: properties.stringify_keys,
        converted_at: Time.current
      )
    end
  end
end
