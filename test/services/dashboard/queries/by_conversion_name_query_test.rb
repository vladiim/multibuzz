# frozen_string_literal: true

require "test_helper"

module Dashboard
  module Queries
    class ByConversionNameQueryTest < ActiveSupport::TestCase
      setup do
        AttributionCredit.delete_all
        Conversion.where(account: account).delete_all
      end

      # ==========================================
      # Built-in dimension tests (conversion_type, funnel)
      # ==========================================

      test "groups by conversion_type dimension" do
        create_credit_for_conversion(conversion_type: "signup", credit: 1.0, revenue_credit: 100)
        create_credit_for_conversion(conversion_type: "signup", credit: 0.5, revenue_credit: 50)
        create_credit_for_conversion(conversion_type: "purchase", credit: 1.0, revenue_credit: 200)

        result = query(dimension: "conversion_type").call

        signup = result.find { |r| r[:channel] == "signup" }
        purchase = result.find { |r| r[:channel] == "purchase" }

        assert_equal 1.5, signup[:credits]
        assert_equal 150.0, signup[:revenue]
        assert_equal 1.0, purchase[:credits]
        assert_equal 200.0, purchase[:revenue]
      end

      test "groups by funnel dimension" do
        create_credit_for_conversion(funnel: "checkout", credit: 1.0)
        create_credit_for_conversion(funnel: "checkout", credit: 1.0)
        create_credit_for_conversion(funnel: "onboarding", credit: 1.0)

        result = query(dimension: "funnel").call

        checkout = result.find { |r| r[:channel] == "checkout" }
        onboarding = result.find { |r| r[:channel] == "onboarding" }

        assert_equal 2.0, checkout[:credits]
        assert_equal 1.0, onboarding[:credits]
      end

      # ==========================================
      # Property dimension tests - FLAT structure
      # Properties are stored flat: { "location" => "Sydney" }
      # NOT nested: { "properties" => { "location" => "Sydney" } }
      # ==========================================

      test "groups by property dimension from flat properties structure" do
        create_credit_for_conversion_with_flat_properties(
          { "location" => "Sydney" },
          credit: 1.0,
          revenue_credit: 100
        )
        create_credit_for_conversion_with_flat_properties(
          { "location" => "Sydney" },
          credit: 0.5,
          revenue_credit: 50
        )
        create_credit_for_conversion_with_flat_properties(
          { "location" => "Melbourne" },
          credit: 1.0,
          revenue_credit: 200
        )

        result = query(dimension: "location").call

        sydney = result.find { |r| r[:channel] == "Sydney" }
        melbourne = result.find { |r| r[:channel] == "Melbourne" }

        assert_not_nil sydney, "Expected to find Sydney in results"
        assert_not_nil melbourne, "Expected to find Melbourne in results"
        assert_equal 1.5, sydney[:credits]
        assert_equal 150.0, sydney[:revenue]
        assert_equal 1.0, melbourne[:credits]
        assert_equal 200.0, melbourne[:revenue]
      end

      test "groups by plan property" do
        create_credit_for_conversion_with_flat_properties({ "plan" => "pro" }, credit: 1.0)
        create_credit_for_conversion_with_flat_properties({ "plan" => "enterprise" }, credit: 1.0)
        create_credit_for_conversion_with_flat_properties({ "plan" => "pro" }, credit: 0.5)

        result = query(dimension: "plan").call

        pro = result.find { |r| r[:channel] == "pro" }
        enterprise = result.find { |r| r[:channel] == "enterprise" }

        assert_equal 1.5, pro[:credits]
        assert_equal 1.0, enterprise[:credits]
      end

      test "handles conversions without the property as not set" do
        create_credit_for_conversion_with_flat_properties({ "location" => "Sydney" }, credit: 0.5)
        create_credit_for_conversion_with_flat_properties({ "plan" => "pro" }, credit: 0.3) # no location
        create_credit_for_conversion_with_flat_properties({}, credit: 0.2) # empty properties

        result = query(dimension: "location").call

        sydney = result.find { |r| r[:channel] == "Sydney" }
        not_set = result.find { |r| r[:channel] == "(not set)" }

        assert_not_nil sydney, "Expected to find Sydney in results"
        assert_not_nil not_set, "Expected to find (not set) in results"
        assert_equal 0.5, sydney[:credits]
        assert_equal 0.5, not_set[:credits]
      end

      test "works with properties alongside url and referrer" do
        # Real-world structure: url, referrer, and custom properties all at root
        conversion = account.conversions.create!(
          visitor: visitor,
          conversion_type: "purchase",
          properties: {
            "url" => "https://example.com/checkout",
            "referrer" => "https://example.com/cart",
            "location" => "Port Melbourne"
          },
          converted_at: 5.days.ago
        )

        account.attribution_credits.create!(
          conversion: conversion,
          attribution_model: attribution_model,
          session_id: rand(100..999),
          channel: Channels::DIRECT,
          credit: 1.0,
          revenue_credit: 100,
          is_test: false
        )

        result = query(dimension: "location").call

        port_melbourne = result.find { |r| r[:channel] == "Port Melbourne" }
        assert_not_nil port_melbourne
        assert_equal 1.0, port_melbourne[:credits]
      end

      # ==========================================
      # Result structure tests
      # ==========================================

      test "returns percentage for each row" do
        create_credit_for_conversion(conversion_type: "signup", credit: 0.75)
        create_credit_for_conversion(conversion_type: "purchase", credit: 0.25)

        result = query(dimension: "conversion_type").call

        signup = result.find { |r| r[:channel] == "signup" }
        purchase = result.find { |r| r[:channel] == "purchase" }

        assert_equal 75.0, signup[:percentage]
        assert_equal 25.0, purchase[:percentage]
      end

      test "returns conversion count for each row" do
        # Two credits for same conversion
        conversion = create_conversion(conversion_type: "signup")
        create_credit(conversion: conversion, credit: 0.5)
        create_credit(conversion: conversion, credit: 0.5)

        # One credit for another conversion
        create_credit_for_conversion(conversion_type: "signup", credit: 1.0)

        result = query(dimension: "conversion_type").call

        signup = result.find { |r| r[:channel] == "signup" }
        assert_equal 2, signup[:conversion_count]
      end

      test "sorts results by credits descending" do
        create_credit_for_conversion(conversion_type: "low", credit: 0.2)
        create_credit_for_conversion(conversion_type: "high", credit: 1.0)
        create_credit_for_conversion(conversion_type: "medium", credit: 0.5)

        result = query(dimension: "conversion_type").call

        assert_equal %w[high medium low], result.map { |r| r[:channel] }
      end

      test "limits results to specified limit" do
        10.times { |i| create_credit_for_conversion(conversion_type: "type_#{i}", credit: 0.1) }

        result = query(dimension: "conversion_type", limit: 5).call

        assert_equal 5, result.size
      end

      test "returns empty array when no credits exist" do
        result = query(dimension: "conversion_type").call

        assert_equal [], result
      end

      private

      def query(dimension: "conversion_type", limit: 10)
        scope = account.attribution_credits.joins(:conversion)
        ByConversionNameQuery.new(scope, dimension: dimension, limit: limit)
      end

      def account
        @account ||= accounts(:one)
      end

      def visitor
        @visitor ||= visitors(:one)
      end

      def attribution_model
        @attribution_model ||= attribution_models(:first_touch)
      end

      def create_conversion(conversion_type: "signup", funnel: nil, properties: {})
        account.conversions.create!(
          visitor: visitor,
          conversion_type: conversion_type,
          funnel: funnel,
          properties: properties,
          converted_at: 5.days.ago
        )
      end

      def create_credit(conversion:, credit: 1.0, revenue_credit: 0)
        account.attribution_credits.create!(
          conversion: conversion,
          attribution_model: attribution_model,
          session_id: rand(100..999),
          channel: Channels::DIRECT,
          credit: credit,
          revenue_credit: revenue_credit,
          is_test: false
        )
      end

      def create_credit_for_conversion(conversion_type: "signup", funnel: nil, credit: 1.0, revenue_credit: 0)
        conversion = create_conversion(conversion_type: conversion_type, funnel: funnel)
        create_credit(conversion: conversion, credit: credit, revenue_credit: revenue_credit)
      end

      def create_credit_for_conversion_with_flat_properties(properties, credit: 1.0, revenue_credit: 0)
        conversion = create_conversion(properties: properties)
        create_credit(conversion: conversion, credit: credit, revenue_credit: revenue_credit)
      end
    end
  end
end
