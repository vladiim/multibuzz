# frozen_string_literal: true

require "test_helper"

module Dashboard
  class ConversionDimensionsServiceTest < ActiveSupport::TestCase
    setup do
      ConversionPropertyKey.where(account: account).delete_all
    end

    # ==========================================
    # Built-in dimensions
    # ==========================================

    test "returns built-in dimensions" do
      result = service.call

      assert result[:success]
      dimensions = result[:dimensions]

      conversion_type = dimensions.find { |d| d[:key] == "conversion_type" }
      funnel = dimensions.find { |d| d[:key] == "funnel" }
      revenue = dimensions.find { |d| d[:key] == "revenue" }

      assert_equal "Conversion Name", conversion_type[:label]
      assert_equal "column", conversion_type[:type]

      assert_equal "Funnel", funnel[:label]
      assert_equal "column", funnel[:type]

      assert_equal "Revenue", revenue[:label]
      assert_equal "numeric", revenue[:type]
    end

    # ==========================================
    # Property dimensions from discovered keys
    # ==========================================

    test "returns property dimensions from discovered keys" do
      create_property_key("location")
      create_property_key("plan")

      result = service.call

      assert result[:success]
      dimensions = result[:dimensions]

      location = dimensions.find { |d| d[:key] == "location" }
      plan = dimensions.find { |d| d[:key] == "plan" }

      assert_not_nil location
      assert_equal "Location", location[:label]
      assert_equal "property", location[:type]

      assert_not_nil plan
      assert_equal "Plan", plan[:label]
      assert_equal "property", plan[:type]
    end

    test "orders property dimensions by popularity" do
      create_property_key("rare_key", occurrences: 5)
      create_property_key("popular_key", occurrences: 100)
      create_property_key("medium_key", occurrences: 50)

      result = service.call
      property_dims = result[:dimensions].select { |d| d[:type] == "property" }

      keys = property_dims.map { |d| d[:key] }

      assert_equal %w[popular_key medium_key rare_key], keys
    end

    test "limits property dimensions to 20" do
      25.times { |i| create_property_key("key_#{i}", occurrences: 25 - i) }

      result = service.call
      property_dims = result[:dimensions].select { |d| d[:type] == "property" }

      assert_equal 20, property_dims.size
    end

    test "excludes stale property keys" do
      create_property_key("fresh_key", last_seen_at: 1.day.ago)
      create_property_key("stale_key", last_seen_at: 100.days.ago)

      result = service.call
      keys = result[:dimensions].map { |d| d[:key] }

      assert_includes keys, "fresh_key"
      refute_includes keys, "stale_key"
    end

    # ==========================================
    # Multi-account isolation
    # ==========================================

    test "only returns property keys for specified account" do
      create_property_key("our_key")

      # Create key for different account
      other_account = accounts(:two)
      other_account.conversion_property_keys.create!(
        property_key: "their_key",
        occurrences: 10,
        last_seen_at: Time.current
      )

      result = service.call
      keys = result[:dimensions].map { |d| d[:key] }

      assert_includes keys, "our_key"
      refute_includes keys, "their_key"
    end

    private

    def service
      @service ||= ConversionDimensionsService.new(account)
    end

    def account
      @account ||= accounts(:one)
    end

    def create_property_key(key, occurrences: 10, last_seen_at: Time.current)
      account.conversion_property_keys.create!(
        property_key: key,
        occurrences: occurrences,
        last_seen_at: last_seen_at
      )
    end
  end
end
