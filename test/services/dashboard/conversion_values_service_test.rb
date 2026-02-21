# frozen_string_literal: true

require "test_helper"

module Dashboard
  class ConversionValuesServiceTest < ActiveSupport::TestCase
    setup do
      # Delete in correct order due to foreign key constraints
      AttributionCredit.where(account: account).delete_all
      Conversion.where(account: account).delete_all
      ConversionPropertyKey.where(account: account).delete_all
    end

    # ==========================================
    # Column field tests (conversion_type, funnel)
    # ==========================================

    test "returns distinct values for conversion_type column" do
      create_conversion(conversion_type: "signup")
      create_conversion(conversion_type: "purchase")
      create_conversion(conversion_type: "signup") # duplicate

      result = service(field: "conversion_type").call

      assert result[:success]
      assert_includes result[:values], "signup"
      assert_includes result[:values], "purchase"
      assert_equal 2, result[:values].size
    end

    test "returns distinct values for funnel column" do
      create_conversion(funnel: "subscription")
      create_conversion(funnel: "lead")
      create_conversion(funnel: nil) # should be excluded

      result = service(field: "funnel").call

      assert result[:success]
      assert_includes result[:values], "subscription"
      assert_includes result[:values], "lead"
      refute_includes result[:values], nil
    end

    test "filters column values by query" do
      create_conversion(conversion_type: "signup")
      create_conversion(conversion_type: "signup_complete")
      create_conversion(conversion_type: "purchase")

      result = service(field: "conversion_type", query: "sign").call

      assert result[:success]
      assert_includes result[:values], "signup"
      assert_includes result[:values], "signup_complete"
      refute_includes result[:values], "purchase"
    end

    # ==========================================
    # Property field tests - FLAT structure
    # Properties should be stored flat at root level:
    # { "url" => "...", "location" => "Sydney" }
    # NOT nested: { "properties" => { "location" => "Sydney" } }
    # ==========================================

    test "returns distinct values for property keys from flat properties structure" do
      create_conversion_with_flat_properties(location: "Sydney")
      create_conversion_with_flat_properties(location: "Melbourne")
      create_conversion_with_flat_properties(location: "Sydney") # duplicate

      result = service(field: "location").call

      assert result[:success], "Expected success but got: #{result[:errors]}"
      assert_includes result[:values], "Sydney"
      assert_includes result[:values], "Melbourne"
      assert_equal 2, result[:values].size
    end

    test "returns distinct values for plan property" do
      create_conversion_with_flat_properties(plan: "pro")
      create_conversion_with_flat_properties(plan: "enterprise")
      create_conversion_with_flat_properties(plan: "free")

      result = service(field: "plan").call

      assert result[:success]
      assert_includes result[:values], "pro"
      assert_includes result[:values], "enterprise"
      assert_includes result[:values], "free"
    end

    test "filters property values by query" do
      create_conversion_with_flat_properties(location: "Port Melbourne")
      create_conversion_with_flat_properties(location: "Melbourne")
      create_conversion_with_flat_properties(location: "Sydney")

      result = service(field: "location", query: "Melbourne").call

      assert result[:success]
      assert_includes result[:values], "Port Melbourne"
      assert_includes result[:values], "Melbourne"
      refute_includes result[:values], "Sydney"
    end

    test "handles conversions without the specified property key" do
      create_conversion_with_flat_properties(location: "Sydney")
      create_conversion_with_flat_properties(plan: "pro") # no location
      create_conversion_with_flat_properties({}) # empty properties

      result = service(field: "location").call

      assert result[:success]
      assert_equal [ "Sydney" ], result[:values]
    end

    test "returns values from properties alongside url and referrer" do
      # Real-world structure: url, referrer, and custom properties all at root
      account.conversions.create!(
        visitor: visitor,
        conversion_type: "purchase",
        properties: {
          "url" => "https://example.com/checkout",
          "referrer" => "https://example.com/cart",
          "location" => "Sydney",
          "plan" => "pro"
        },
        converted_at: Time.current
      )

      location_result = service(field: "location").call
      plan_result = service(field: "plan").call

      assert_includes location_result[:values], "Sydney"
      assert_includes plan_result[:values], "pro"
    end

    # ==========================================
    # Edge cases
    # ==========================================

    test "returns error when field is blank" do
      result = service(field: "").call

      refute result[:success]
      assert_includes result[:errors], "field is required"
    end

    test "returns empty array when no conversions exist" do
      result = service(field: "location").call

      assert result[:success]
      assert_empty result[:values]
    end

    test "limits results to 20 values" do
      25.times { |i| create_conversion_with_flat_properties(location: "City #{i}") }

      result = service(field: "location").call

      assert result[:success]
      assert_equal 20, result[:values].size
    end

    test "respects test_mode flag" do
      create_conversion_with_flat_properties({ location: "Sydney" }, is_test: false)
      create_conversion_with_flat_properties({ location: "Melbourne" }, is_test: true)

      prod_result = service(field: "location", test_mode: false).call
      test_result = service(field: "location", test_mode: true).call

      assert_equal [ "Sydney" ], prod_result[:values]
      assert_equal [ "Melbourne" ], test_result[:values]
    end

    # ==========================================
    # Multi-account isolation
    # ==========================================

    test "only returns values for specified account" do
      create_conversion_with_flat_properties(location: "Sydney")

      # Create conversion for different account
      other_account = accounts(:two)
      other_account.conversions.create!(
        visitor: visitors(:three),
        conversion_type: "signup",
        properties: { "location" => "Perth" },
        converted_at: Time.current
      )

      result = service(field: "location").call

      assert result[:success]
      assert_includes result[:values], "Sydney"
      refute_includes result[:values], "Perth"
    end

    private

    def service(field:, query: nil, test_mode: false)
      ConversionValuesService.new(
        account,
        field: field,
        query: query,
        test_mode: test_mode
      )
    end

    def account
      @account ||= accounts(:one)
    end

    def visitor
      @visitor ||= visitors(:one)
    end

    def create_conversion(conversion_type: "signup", funnel: nil, is_test: false)
      account.conversions.create!(
        visitor: visitor,
        conversion_type: conversion_type,
        funnel: funnel,
        is_test: is_test,
        converted_at: Time.current
      )
    end

    def create_conversion_with_flat_properties(properties = {}, is_test: false, **extra_properties)
      # Allow both hash argument and keyword arguments
      props = properties.empty? ? extra_properties : properties
      account.conversions.create!(
        visitor: visitor,
        conversion_type: "signup",
        properties: props.stringify_keys,
        is_test: is_test,
        converted_at: Time.current
      )
    end
  end
end
