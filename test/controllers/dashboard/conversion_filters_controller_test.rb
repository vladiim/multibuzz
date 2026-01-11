# frozen_string_literal: true

require "test_helper"

module Dashboard
  class ConversionFiltersControllerTest < ActionDispatch::IntegrationTest
    setup do
      # Enable live mode so default view mode is production
      accounts(:one).update!(live_mode_enabled: true)
      sign_in_as users(:one)
    end

    # ==========================================
    # Dimensions endpoint tests
    # ==========================================

    test "dimensions returns built-in dimensions" do
      get dashboard_conversion_filters_dimensions_path

      assert_response :success

      dimensions = response.parsed_body
      assert_kind_of Array, dimensions

      # Should include conversion_type as first dimension
      conversion_type = dimensions.find { |d| d["key"] == "conversion_type" }
      assert_not_nil conversion_type
      assert_equal "Conversion Name", conversion_type["label"]
      assert_equal "column", conversion_type["type"]

      # Should include funnel
      funnel = dimensions.find { |d| d["key"] == "funnel" }
      assert_not_nil funnel
      assert_equal "Funnel", funnel["label"]

      # Should include revenue
      revenue = dimensions.find { |d| d["key"] == "revenue" }
      assert_not_nil revenue
      assert_equal "numeric", revenue["type"]
    end

    test "dimensions includes discovered property keys" do
      create_property_key("product_id", occurrences: 10)
      create_property_key("plan", occurrences: 5)

      get dashboard_conversion_filters_dimensions_path

      assert_response :success

      dimensions = response.parsed_body
      product_id = dimensions.find { |d| d["key"] == "product_id" }
      plan = dimensions.find { |d| d["key"] == "plan" }

      assert_not_nil product_id
      assert_equal "Product", product_id["label"]
      assert_equal "property", product_id["type"]

      assert_not_nil plan
      assert_equal "Plan", plan["label"]
    end

    test "dimensions orders property keys by popularity" do
      create_property_key("rare_key", occurrences: 1)
      create_property_key("popular_key", occurrences: 100)

      get dashboard_conversion_filters_dimensions_path

      assert_response :success

      dimensions = response.parsed_body
      property_dimensions = dimensions.select { |d| d["type"] == "property" }

      # More popular should come first
      assert_equal "popular_key", property_dimensions.first["key"]
    end

    test "dimensions excludes stale property keys" do
      create_property_key("fresh_key", occurrences: 5, last_seen_at: 10.days.ago)
      create_property_key("stale_key", occurrences: 5, last_seen_at: 60.days.ago)

      get dashboard_conversion_filters_dimensions_path

      assert_response :success

      dimensions = response.parsed_body
      keys = dimensions.map { |d| d["key"] }

      assert_includes keys, "fresh_key"
      refute_includes keys, "stale_key"
    end

    test "dimensions limits property keys to 20" do
      25.times { |i| create_property_key("prop_#{i}", occurrences: i) }

      get dashboard_conversion_filters_dimensions_path

      assert_response :success

      dimensions = response.parsed_body
      property_dimensions = dimensions.select { |d| d["type"] == "property" }

      assert_equal 20, property_dimensions.length
    end

    test "dimensions requires authentication" do
      delete logout_path
      get dashboard_conversion_filters_dimensions_path

      assert_redirected_to login_path
    end

    # ==========================================
    # Values endpoint tests
    # ==========================================

    test "values returns distinct conversion_type values" do
      create_conversion(conversion_type: "signup")
      create_conversion(conversion_type: "purchase")
      create_conversion(conversion_type: "signup") # duplicate

      get dashboard_conversion_filters_values_path(field: "conversion_type")

      assert_response :success

      values = response.parsed_body
      assert_includes values, "signup"
      assert_includes values, "purchase"
      assert_equal 2, values.length
    end

    test "values returns distinct funnel values" do
      create_conversion(funnel: "subscription")
      create_conversion(funnel: "lead")
      create_conversion(funnel: nil)

      get dashboard_conversion_filters_values_path(field: "funnel")

      assert_response :success

      values = response.parsed_body
      assert_includes values, "subscription"
      assert_includes values, "lead"
      refute_includes values, nil
    end

    test "values filters by query parameter" do
      create_conversion(conversion_type: "signup")
      create_conversion(conversion_type: "sign_in")
      create_conversion(conversion_type: "purchase")

      get dashboard_conversion_filters_values_path(field: "conversion_type", query: "sign")

      assert_response :success

      values = response.parsed_body
      assert_includes values, "signup"
      assert_includes values, "sign_in"
      refute_includes values, "purchase"
    end

    test "values returns property values from JSONB" do
      create_conversion(properties: { "plan" => "pro" })
      create_conversion(properties: { "plan" => "enterprise" })
      create_conversion(properties: { "plan" => "pro" }) # duplicate

      get dashboard_conversion_filters_values_path(field: "plan")

      assert_response :success

      values = response.parsed_body
      assert_includes values, "pro"
      assert_includes values, "enterprise"
      assert_equal 2, values.length
    end

    test "values limits results to 20" do
      25.times { |i| create_conversion(conversion_type: "type_#{i}") }

      get dashboard_conversion_filters_values_path(field: "conversion_type")

      assert_response :success

      values = response.parsed_body
      assert_equal 20, values.length
    end

    test "values requires authentication" do
      delete logout_path
      get dashboard_conversion_filters_values_path(field: "conversion_type")

      assert_redirected_to login_path
    end

    test "values scopes to current account only" do
      create_conversion(conversion_type: "my_account_type")

      # Create conversion for different account
      other_account = accounts(:two)
      other_account.conversions.create!(
        visitor: other_account.visitors.create!(
          visitor_id: "other_visitor",
          first_seen_at: Time.current,
          last_seen_at: Time.current
        ),
        conversion_type: "other_account_type",
        converted_at: Time.current
      )

      get dashboard_conversion_filters_values_path(field: "conversion_type")

      assert_response :success

      values = response.parsed_body
      assert_includes values, "my_account_type"
      refute_includes values, "other_account_type"
    end

    # ==========================================
    # Add row endpoint tests (Turbo Stream)
    # ==========================================

    test "add_row returns turbo stream with new filter row" do
      post dashboard_conversion_filters_add_row_path,
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_match "turbo-stream", response.content_type
      assert_match "append", response.body
      assert_match "conversion-filters", response.body
    end

    test "add_row includes field select with dimensions" do
      create_property_key("plan", occurrences: 5)

      post dashboard_conversion_filters_add_row_path,
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_match "conversion_type", response.body
      assert_match "funnel", response.body
      assert_match "plan", response.body
    end

    test "add_row accepts index parameter for form naming" do
      post dashboard_conversion_filters_add_row_path(index: 2),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_match "conversion_filters[2]", response.body
    end

    test "add_row requires authentication" do
      delete logout_path
      post dashboard_conversion_filters_add_row_path,
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_redirected_to login_path
    end

    # ==========================================
    # Remove row endpoint tests (Turbo Stream)
    # ==========================================

    test "remove_row returns turbo stream removing the row" do
      delete dashboard_conversion_filters_remove_row_path(row_id: "filter-row-0"),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_response :success
      assert_match "turbo-stream", response.content_type
      assert_match "remove", response.body
      assert_match "filter-row-0", response.body
    end

    test "remove_row requires authentication" do
      delete logout_path
      delete dashboard_conversion_filters_remove_row_path(row_id: "filter-row-0"),
        headers: { "Accept" => "text/vnd.turbo-stream.html" }

      assert_redirected_to login_path
    end

    private

    def sign_in_as(user)
      post login_path, params: { email: user.email, password: "password123" }
    end

    def account
      @account ||= accounts(:one)
    end

    def visitor
      @visitor ||= visitors(:one)
    end

    def create_property_key(key, occurrences: 1, last_seen_at: Time.current)
      account.conversion_property_keys.create!(
        property_key: key,
        occurrences: occurrences,
        last_seen_at: last_seen_at
      )
    end

    def create_conversion(conversion_type: "test", funnel: nil, properties: {})
      account.conversions.create!(
        visitor: visitor,
        conversion_type: conversion_type,
        funnel: funnel,
        properties: properties,
        converted_at: Time.current,
        is_test: false  # Create production data since we're testing in production mode
      )
    end
  end
end
