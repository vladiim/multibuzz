# frozen_string_literal: true

require "test_helper"

module Dashboard
  module Scopes
    class FilteredCreditsScopeTest < ActiveSupport::TestCase
      setup do
        # Clear any existing credits from fixtures
        account.attribution_credits.delete_all
        account.conversions.delete_all

        # Create conversions with FLAT properties structure
        # Properties are stored flat at root level, not nested
        @purchase_conversion = create_conversion(
          conversion_type: "purchase",
          funnel: "checkout",
          revenue: 100.0,
          properties: { "plan" => "pro", "source" => "web" }
        )
        @signup_conversion = create_conversion(
          conversion_type: "signup",
          funnel: "onboarding",
          revenue: 10.0,
          properties: { "plan" => "free", "source" => "mobile" }
        )
      end

      test "returns all credits when no filters applied" do
        result = scope(conversion_filters: []).call

        assert_equal 2, result.count
      end

      test "filters by conversion_type with equals operator" do
        filters = [{ field: "conversion_type", operator: "equals", values: ["purchase"] }]

        result = scope(conversion_filters: filters).call

        assert_equal 1, result.count
        assert_equal @purchase_conversion.id, result.first.conversion_id
      end

      test "filters by conversion_type with not_equals operator" do
        filters = [{ field: "conversion_type", operator: "not_equals", values: ["purchase"] }]

        result = scope(conversion_filters: filters).call

        assert_equal 1, result.count
        assert_equal @signup_conversion.id, result.first.conversion_id
      end

      test "filters by funnel column" do
        filters = [{ field: "funnel", operator: "equals", values: ["checkout"] }]

        result = scope(conversion_filters: filters).call

        assert_equal 1, result.count
        assert_equal @purchase_conversion.id, result.first.conversion_id
      end

      test "filters by revenue with greater_than operator" do
        filters = [{ field: "revenue", operator: "greater_than", values: ["50"] }]

        result = scope(conversion_filters: filters).call

        assert_equal 1, result.count
        assert_equal @purchase_conversion.id, result.first.conversion_id
      end

      test "filters by revenue with less_than operator" do
        filters = [{ field: "revenue", operator: "less_than", values: ["50"] }]

        result = scope(conversion_filters: filters).call

        assert_equal 1, result.count
        assert_equal @signup_conversion.id, result.first.conversion_id
      end

      test "filters by JSONB property with equals operator" do
        filters = [{ field: "plan", operator: "equals", values: ["pro"] }]

        result = scope(conversion_filters: filters).call

        assert_equal 1, result.count
        assert_equal @purchase_conversion.id, result.first.conversion_id
      end

      test "filters by JSONB property with contains operator" do
        filters = [{ field: "source", operator: "contains", values: ["mob"] }]

        result = scope(conversion_filters: filters).call

        assert_equal 1, result.count
        assert_equal @signup_conversion.id, result.first.conversion_id
      end

      test "supports multiple values with OR logic" do
        filters = [{ field: "conversion_type", operator: "equals", values: %w[purchase signup] }]

        result = scope(conversion_filters: filters).call

        assert_equal 2, result.count
      end

      test "combines multiple filters with AND logic" do
        filters = [
          { field: "conversion_type", operator: "equals", values: ["purchase"] },
          { field: "plan", operator: "equals", values: ["pro"] }
        ]

        result = scope(conversion_filters: filters).call

        assert_equal 1, result.count
        assert_equal @purchase_conversion.id, result.first.conversion_id
      end

      test "returns empty when filters exclude all" do
        filters = [
          { field: "conversion_type", operator: "equals", values: ["purchase"] },
          { field: "plan", operator: "equals", values: ["free"] }
        ]

        result = scope(conversion_filters: filters).call

        assert_empty result
      end

      private

      def scope(conversion_filters:)
        FilteredCreditsScope.new(
          account: account,
          models: [attribution_model],
          date_range: date_range,
          channels: Channels::ALL,
          test_mode: false,
          conversion_filters: conversion_filters
        )
      end

      def account
        @account ||= accounts(:one)
      end

      def visitor
        @visitor ||= visitors(:one)
      end

      def attribution_model
        @attribution_model ||= account.attribution_models.first
      end

      def date_range
        @date_range ||= Dashboard::DateRangeParser.new("30d")
      end

      def create_conversion(conversion_type:, funnel:, revenue:, properties:)
        conversion = account.conversions.create!(
          visitor: visitor,
          conversion_type: conversion_type,
          funnel: funnel,
          revenue: revenue,
          properties: properties,
          converted_at: 1.day.ago
        )

        # Create attribution credit for this conversion
        account.attribution_credits.create!(
          conversion: conversion,
          session_id: sessions(:one).id,
          attribution_model: attribution_model,
          channel: "direct",
          credit: 1.0,
          revenue_credit: revenue,
          is_test: false
        )

        conversion
      end
    end
  end
end
