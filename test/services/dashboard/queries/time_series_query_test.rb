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

      private

      def query
        TimeSeriesQuery.new(build_scope, date_range: date_range)
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

      def create_credit_on_date(date, channel:, credit:)
        conversion = create_conversion(converted_at: date.to_datetime)
        account.attribution_credits.create!(
          conversion: conversion,
          attribution_model: attribution_model,
          session_id: rand(100..999),
          channel: channel,
          credit: credit,
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
