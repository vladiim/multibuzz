# frozen_string_literal: true

require "test_helper"

module Dashboard
  module Queries
    class TimeSeriesQueryTest < ActiveSupport::TestCase
      setup do
        AttributionCredit.delete_all
        Conversion.where(account: account).delete_all
      end

      test "returns daily credits for each channel" do
        create_credit_on_date(5.days.ago.to_date, channel: Channels::PAID_SEARCH, credit: 1.0)
        create_credit_on_date(3.days.ago.to_date, channel: Channels::PAID_SEARCH, credit: 0.5)
        create_credit_on_date(3.days.ago.to_date, channel: Channels::EMAIL, credit: 1.0)

        result = query.call

        assert result[:dates].is_a?(Array)
        assert result[:series].is_a?(Array)

        paid_search_series = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        assert paid_search_series.present?, "Should have paid_search series"

        data_sum = paid_search_series[:data].sum
        assert_operator data_sum, :>, 0, "Paid search series should have non-zero data"
      end

      test "returns correct number of dates for date range" do
        create_credit_on_date(2.days.ago.to_date, channel: Channels::PAID_SEARCH, credit: 1.0)

        result = query.call

        assert_equal 7, result[:dates].length
      end

      test "handles empty data gracefully" do
        result = query.call

        assert result[:dates].is_a?(Array)
        assert result[:series].empty?
      end

      test "limits to top channels by credit volume" do
        # Create multiple credits per channel to vary total credit volume
        # Credits must be <= 1.0 per record
        6.times do |i|
          (6 - i).times do
            create_credit_on_date(2.days.ago.to_date, channel: Channels::ALL[i], credit: 1.0)
          end
        end

        result = query.call

        assert_equal 5, result[:series].length
      end

      # ==========================================
      # Metric Support Tests
      # ==========================================

      test "returns credits by default" do
        create_credit_on_date(3.days.ago.to_date, channel: Channels::PAID_SEARCH, credit: 0.5, revenue_credit: 100.0)

        result = query.call

        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        assert_equal 0.5, paid_search[:data].sum
      end

      test "returns revenue when metric is revenue" do
        create_credit_on_date(3.days.ago.to_date, channel: Channels::PAID_SEARCH, credit: 0.5, revenue_credit: 100.0)
        create_credit_on_date(3.days.ago.to_date, channel: Channels::EMAIL, credit: 0.5, revenue_credit: 50.0)

        result = query(metric: "revenue").call

        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        email = result[:series].find { |s| s[:channel] == Channels::EMAIL }

        assert_equal 100.0, paid_search[:data].sum
        assert_equal 50.0, email[:data].sum
      end

      test "returns conversion count when metric is conversions" do
        # Two credits for same conversion should count as 1 conversion
        conversion = create_conversion(converted_at: 3.days.ago.to_datetime)
        create_credit_for_conversion(conversion, channel: Channels::PAID_SEARCH, credit: 0.5)
        create_credit_for_conversion(conversion, channel: Channels::EMAIL, credit: 0.5)

        # Another conversion
        conversion2 = create_conversion(converted_at: 3.days.ago.to_datetime)
        create_credit_for_conversion(conversion2, channel: Channels::PAID_SEARCH, credit: 1.0)

        result = query(metric: "conversions").call

        # paid_search has credits from 2 conversions
        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        assert_equal 2.0, paid_search[:data].sum

        # email has credit from 1 conversion
        email = result[:series].find { |s| s[:channel] == Channels::EMAIL }
        assert_equal 1.0, email[:data].sum
      end

      test "top channels ordered by selected metric" do
        # Create data where revenue ordering differs from credit ordering
        create_credit_on_date(2.days.ago.to_date, channel: Channels::PAID_SEARCH, credit: 1.0, revenue_credit: 10.0)
        create_credit_on_date(2.days.ago.to_date, channel: Channels::EMAIL, credit: 0.5, revenue_credit: 100.0)

        credits_result = query(metric: "credits").call
        revenue_result = query(metric: "revenue").call

        # Credits: paid_search first (1.0 > 0.5)
        assert_equal Channels::PAID_SEARCH, credits_result[:series].first[:channel]

        # Revenue: email first (100.0 > 10.0)
        assert_equal Channels::EMAIL, revenue_result[:series].first[:channel]
      end

      private

      def query(metric: nil)
        TimeSeriesQuery.new(build_scope, date_range: date_range, metric: metric)
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
        @date_range ||= DateRangeParser.new("7d")
      end

      def account
        @account ||= accounts(:one)
      end

      def attribution_model
        @attribution_model ||= attribution_models(:first_touch)
      end

      def create_credit_on_date(date, channel:, credit:, revenue_credit: 0.0)
        conversion = create_conversion(converted_at: date.to_datetime)
        create_credit_for_conversion(conversion, channel: channel, credit: credit, revenue_credit: revenue_credit)
      end

      def create_credit_for_conversion(conversion, channel:, credit:, revenue_credit: 0.0)
        account.attribution_credits.create!(
          conversion: conversion,
          attribution_model: attribution_model,
          session_id: rand(100..999),
          channel: channel,
          credit: credit,
          revenue_credit: revenue_credit,
          is_test: false
        )
      end

      def create_conversion(converted_at:)
        account.conversions.create!(
          visitor: visitors(:one),
          conversion_type: "purchase",
          converted_at: converted_at
        )
      end
    end
  end
end
