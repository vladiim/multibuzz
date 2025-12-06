# frozen_string_literal: true

require "test_helper"

module Dashboard
  module Queries
    class TotalsQueryTest < ActiveSupport::TestCase
      setup do
        AttributionCredit.delete_all
        Conversion.where(account: account).delete_all
      end

      test "returns conversions as sum of credits" do
        create_credit(credit: 0.5)
        create_credit(credit: 0.3)
        create_credit(credit: 0.2)

        result = query.call

        assert_equal 1.0, result[:conversions]
      end

      test "returns revenue as sum of revenue_credit" do
        create_credit(credit: 0.5, revenue_credit: 50.0)
        create_credit(credit: 0.5, revenue_credit: 100.0)

        result = query.call

        assert_equal 150.0, result[:revenue]
      end

      test "returns aov as revenue divided by conversions" do
        create_credit(credit: 0.5, revenue_credit: 50.0)
        create_credit(credit: 0.5, revenue_credit: 50.0)

        result = query.call

        assert_equal 100.0, result[:aov]
      end

      test "returns avg_channels_to_convert" do
        # Conversion 1: 2 channels (paid_search, email)
        conv1 = create_conversion
        create_credit_for_conversion(conv1, channel: Channels::PAID_SEARCH)
        create_credit_for_conversion(conv1, channel: Channels::EMAIL)

        # Conversion 2: 3 channels (paid_search, email, direct)
        conv2 = create_conversion
        create_credit_for_conversion(conv2, channel: Channels::PAID_SEARCH)
        create_credit_for_conversion(conv2, channel: Channels::EMAIL)
        create_credit_for_conversion(conv2, channel: Channels::DIRECT)

        result = query.call

        # Average: (2 + 3) / 2 = 2.5
        assert_equal 2.5, result[:avg_channels_to_convert]
      end

      test "returns avg_visits_to_convert" do
        # Conversion 1: 2 visits (sessions)
        conv1 = create_conversion
        create_credit_for_conversion(conv1, session_id: 101)
        create_credit_for_conversion(conv1, session_id: 102)

        # Conversion 2: 4 visits
        conv2 = create_conversion
        create_credit_for_conversion(conv2, session_id: 201)
        create_credit_for_conversion(conv2, session_id: 202)
        create_credit_for_conversion(conv2, session_id: 203)
        create_credit_for_conversion(conv2, session_id: 204)

        result = query.call

        # Average: (2 + 4) / 2 = 3.0
        assert_equal 3.0, result[:avg_visits_to_convert]
      end

      test "handles empty data gracefully" do
        result = query.call

        assert_equal 0, result[:conversions]
        assert_equal 0, result[:revenue]
        assert_nil result[:aov]
        assert_nil result[:avg_channels_to_convert]
        assert_nil result[:avg_visits_to_convert]
      end

      private

      def query
        TotalsQuery.new(build_scope)
      end

      def build_scope
        Scopes::CreditsScope.new(
          account: account,
          models: [attribution_model],
          date_range: date_range,
          channels: Channels::ALL
        ).call
      end

      def date_range
        @date_range ||= DateRangeParser.new("30d")
      end

      def account
        @account ||= accounts(:one)
      end

      def attribution_model
        @attribution_model ||= attribution_models(:first_touch)
      end

      def create_credit(credit: 1.0, revenue_credit: nil, channel: Channels::PAID_SEARCH)
        conversion = create_conversion
        create_credit_for_conversion(conversion, credit: credit, revenue_credit: revenue_credit, channel: channel)
      end

      def create_credit_for_conversion(conversion, credit: 0.5, revenue_credit: nil, channel: Channels::PAID_SEARCH, session_id: nil)
        account.attribution_credits.create!(
          conversion: conversion,
          attribution_model: attribution_model,
          session_id: session_id || rand(100..999),
          channel: channel,
          credit: credit,
          revenue_credit: revenue_credit,
          is_test: false
        )
      end

      def create_conversion
        account.conversions.create!(
          visitor: visitors(:one),
          conversion_type: "purchase",
          converted_at: 1.day.ago
        )
      end
    end
  end
end
