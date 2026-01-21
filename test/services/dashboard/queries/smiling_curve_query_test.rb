# frozen_string_literal: true

require "test_helper"

module Dashboard
  module Queries
    class SmilingCurveQueryTest < ActiveSupport::TestCase
      setup do
        AttributionCredit.delete_all
        Conversion.where(account: account).delete_all
        Identity.where(account: account).delete_all
      end

      # ==========================================
      # Structure Tests
      # ==========================================

      test "returns empty result when no acquisitions" do
        result = query.call

        assert_equal [], result[:months]
        assert_equal [], result[:series]
      end

      test "returns months array from 0 to 12" do
        create_acquisition_with_credit(channel: Channels::PAID_SEARCH)

        result = query.call

        assert_equal (0..12).to_a, result[:months]
      end

      test "returns series with channel and data keys" do
        create_acquisition_with_credit(channel: Channels::PAID_SEARCH)

        result = query.call

        assert result[:series].is_a?(Array)
        assert result[:series].first.key?(:channel)
        assert result[:series].first.key?(:data)
      end

      # ==========================================
      # Per-Channel Breakdown Tests
      # ==========================================

      test "returns separate series for each acquisition channel" do
        create_acquisition_with_credit(channel: Channels::PAID_SEARCH)
        create_acquisition_with_credit(channel: Channels::EMAIL)
        create_acquisition_with_credit(channel: Channels::DIRECT)

        result = query.call

        channels = result[:series].map { |s| s[:channel] }
        assert_includes channels, Channels::PAID_SEARCH
        assert_includes channels, Channels::EMAIL
        assert_includes channels, Channels::DIRECT
      end

      test "each channel series has 13 data points for M0-M12" do
        create_acquisition_with_credit(channel: Channels::PAID_SEARCH)

        result = query.call

        series = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        assert_equal 13, series[:data].length
      end

      test "M0 contains acquisition month revenue" do
        identity = create_identity
        # Acquisition with $100 revenue
        create_acquisition_with_credit(
          channel: Channels::PAID_SEARCH,
          identity: identity,
          revenue: 100,
          converted_at: 2.months.ago
        )

        result = query.call

        series = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        assert_equal 100.0, series[:data][0] # M0
      end

      test "subsequent months contain repeat purchase revenue" do
        identity = create_identity
        acquisition_time = 3.months.ago.beginning_of_month + 15.days

        # Acquisition in M0
        create_acquisition_with_credit(
          channel: Channels::PAID_SEARCH,
          identity: identity,
          revenue: 100,
          converted_at: acquisition_time
        )

        # Repeat purchase in M1 (next month)
        create_repeat_purchase(
          identity: identity,
          revenue: 50,
          converted_at: acquisition_time + 1.month
        )

        # Repeat purchase in M2
        create_repeat_purchase(
          identity: identity,
          revenue: 75,
          converted_at: acquisition_time + 2.months
        )

        result = query.call

        series = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        assert_equal 100.0, series[:data][0] # M0
        assert_equal 50.0, series[:data][1]  # M1
        assert_equal 75.0, series[:data][2]  # M2
      end

      test "averages revenue across multiple customers in same channel" do
        # Customer 1: $100 in M0
        identity1 = create_identity
        create_acquisition_with_credit(
          channel: Channels::PAID_SEARCH,
          identity: identity1,
          revenue: 100,
          converted_at: 2.months.ago.beginning_of_month + 10.days
        )

        # Customer 2: $200 in M0
        identity2 = create_identity
        create_acquisition_with_credit(
          channel: Channels::PAID_SEARCH,
          identity: identity2,
          revenue: 200,
          converted_at: 2.months.ago.beginning_of_month + 15.days
        )

        result = query.call

        series = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        # Average of $100 and $200 = $150
        assert_equal 150.0, series[:data][0]
      end

      test "returns numeric values not strings" do
        create_acquisition_with_credit(channel: Channels::PAID_SEARCH, revenue: 100)

        result = query.call

        series = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        assert series[:data].all? { |v| v.is_a?(Numeric) }, "All values should be numeric"
      end

      private

      def query
        SmilingCurveQuery.new(
          account: account,
          acquisition_conversions: acquisition_conversions,
          test_mode: false
        )
      end

      def acquisition_conversions
        account.conversions.where(is_acquisition: true, is_test: false)
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

      def create_identity
        account.identities.create!(
          external_id: "test_#{SecureRandom.hex(8)}",
          first_identified_at: Time.current,
          last_identified_at: Time.current
        )
      end

      def create_acquisition_with_credit(channel:, identity: nil, revenue: 100, converted_at: 2.months.ago)
        identity ||= create_identity

        conversion = account.conversions.create!(
          visitor: visitor,
          identity: identity,
          conversion_type: "purchase",
          revenue: revenue,
          converted_at: converted_at,
          is_acquisition: true,
          journey_session_ids: []
        )

        account.attribution_credits.create!(
          conversion: conversion,
          attribution_model: attribution_model,
          session_id: rand(1000..9999),
          channel: channel,
          credit: 1.0,
          revenue_credit: revenue
        )

        conversion
      end

      def create_repeat_purchase(identity:, revenue:, converted_at:)
        account.conversions.create!(
          visitor: visitor,
          identity: identity,
          conversion_type: "purchase",
          revenue: revenue,
          converted_at: converted_at,
          is_acquisition: false,
          journey_session_ids: []
        )
      end
    end
  end
end
