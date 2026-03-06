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

        assert_kind_of Array, result[:dates]
        assert_kind_of Array, result[:series]

        paid_search_series = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }

        assert_predicate paid_search_series, :present?, "Should have paid_search series"

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

        assert_kind_of Array, result[:dates]
        assert_empty result[:series]
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

        assert_in_delta(0.5, paid_search[:data].sum)
      end

      test "returns revenue when metric is revenue" do
        create_credit_on_date(3.days.ago.to_date, channel: Channels::PAID_SEARCH, credit: 0.5, revenue_credit: 100.0)
        create_credit_on_date(3.days.ago.to_date, channel: Channels::EMAIL, credit: 0.5, revenue_credit: 50.0)

        result = query(metric: DashboardMetrics::REVENUE).call

        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        email = result[:series].find { |s| s[:channel] == Channels::EMAIL }

        assert_in_delta(100.0, paid_search[:data].sum)
        assert_in_delta(50.0, email[:data].sum)
      end

      test "returns conversion count when metric is conversions" do
        # Two credits for same conversion should count as 1 conversion
        conversion = create_conversion(converted_at: 3.days.ago.to_datetime)
        create_credit_for_conversion(conversion, channel: Channels::PAID_SEARCH, credit: 0.5)
        create_credit_for_conversion(conversion, channel: Channels::EMAIL, credit: 0.5)

        # Another conversion
        conversion2 = create_conversion(converted_at: 3.days.ago.to_datetime)
        create_credit_for_conversion(conversion2, channel: Channels::PAID_SEARCH, credit: 1.0)

        result = query(metric: DashboardMetrics::CONVERSIONS).call

        # paid_search has credits from 2 conversions
        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }

        assert_in_delta(2.0, paid_search[:data].sum)

        # email has credit from 1 conversion
        email = result[:series].find { |s| s[:channel] == Channels::EMAIL }

        assert_in_delta(1.0, email[:data].sum)
      end

      test "top channels ordered by selected metric" do
        # Create data where revenue ordering differs from credit ordering
        create_credit_on_date(2.days.ago.to_date, channel: Channels::PAID_SEARCH, credit: 1.0, revenue_credit: 10.0)
        create_credit_on_date(2.days.ago.to_date, channel: Channels::EMAIL, credit: 0.5, revenue_credit: 100.0)

        credits_result = query(metric: DashboardMetrics::CREDITS).call
        revenue_result = query(metric: DashboardMetrics::REVENUE).call

        # Credits: paid_search first (1.0 > 0.5)
        assert_equal Channels::PAID_SEARCH, credits_result[:series].first[:channel]

        # Revenue: email first (100.0 > 10.0)
        assert_equal Channels::EMAIL, revenue_result[:series].first[:channel]
      end

      # ==========================================
      # AOV Metric
      # ==========================================

      test "returns average order value per day per channel" do
        # Day 1: paid_search has 2 credits totaling 1.5, revenue 150 → AOV = 100
        day1 = 3.days.ago.to_date
        c1 = create_conversion(converted_at: day1.to_datetime)
        create_credit_for_conversion(c1, channel: Channels::PAID_SEARCH, credit: 1.0, revenue_credit: 100.0)
        c2 = create_conversion(converted_at: day1.to_datetime)
        create_credit_for_conversion(c2, channel: Channels::PAID_SEARCH, credit: 0.5, revenue_credit: 50.0)

        result = query(metric: DashboardMetrics::AOV).call

        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        day1_value = day_value(paid_search, day1, result[:dates])

        assert_in_delta(100.0, day1_value, 0.01, "AOV should be 150/1.5 = 100")
      end

      test "aov returns zero for days with no credits" do
        create_credit_on_date(3.days.ago.to_date, channel: Channels::PAID_SEARCH, credit: 1.0, revenue_credit: 50.0)

        result = query(metric: DashboardMetrics::AOV).call

        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        empty_day_value = day_value(paid_search, 2.days.ago.to_date, result[:dates])

        assert_in_delta(0.0, empty_day_value)
      end

      # ==========================================
      # Avg Visits Metric
      # ==========================================

      test "returns average journey visits per conversion per day" do
        day1 = 3.days.ago.to_date
        session1 = create_session(started_at: day1.to_datetime - 2.days)
        session2 = create_session(started_at: day1.to_datetime - 1.day)
        session3 = create_session(started_at: day1.to_datetime - 3.hours)

        # Conversion with 3 journey sessions
        c1 = create_conversion(converted_at: day1.to_datetime, journey_session_ids: [ session1.id, session2.id, session3.id ])
        create_credit_for_conversion(c1, channel: Channels::PAID_SEARCH, credit: 1.0)

        # Conversion with 1 journey session
        session4 = create_session(started_at: day1.to_datetime - 1.hour)
        c2 = create_conversion(converted_at: day1.to_datetime, journey_session_ids: [ session4.id ])
        create_credit_for_conversion(c2, channel: Channels::PAID_SEARCH, credit: 1.0)

        result = query(metric: DashboardMetrics::AVG_VISITS).call

        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        day1_value = day_value(paid_search, day1, result[:dates])

        # Average of 3 and 1 = 2.0
        assert_in_delta(2.0, day1_value, 0.1)
      end

      test "avg_visits excludes conversions without journey data" do
        day1 = 3.days.ago.to_date
        session1 = create_session(started_at: day1.to_datetime - 1.day)

        # Conversion WITH journey
        c1 = create_conversion(converted_at: day1.to_datetime, journey_session_ids: [ session1.id ])
        create_credit_for_conversion(c1, channel: Channels::PAID_SEARCH, credit: 1.0)

        # Conversion WITHOUT journey (empty array)
        c2 = create_conversion(converted_at: day1.to_datetime, journey_session_ids: [])
        create_credit_for_conversion(c2, channel: Channels::PAID_SEARCH, credit: 1.0)

        result = query(metric: DashboardMetrics::AVG_VISITS).call

        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        day1_value = day_value(paid_search, day1, result[:dates])

        # Only c1 counted: 1 visit
        assert_in_delta(1.0, day1_value, 0.1)
      end

      # ==========================================
      # Avg Channels Metric
      # ==========================================

      test "returns average distinct channels per conversion per day" do
        day1 = 3.days.ago.to_date

        # Conversion touching 2 channels
        c1 = create_conversion(converted_at: day1.to_datetime)
        create_credit_for_conversion(c1, channel: Channels::PAID_SEARCH, credit: 0.5)
        create_credit_for_conversion(c1, channel: Channels::EMAIL, credit: 0.5)

        # Conversion touching 1 channel
        c2 = create_conversion(converted_at: day1.to_datetime)
        create_credit_for_conversion(c2, channel: Channels::PAID_SEARCH, credit: 1.0)

        result = query(metric: DashboardMetrics::AVG_CHANNELS).call

        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        day1_value = day_value(paid_search, day1, result[:dates])

        # paid_search sees both conversions: c1 has 2 channels, c2 has 1 → avg = 1.5
        assert_in_delta(1.5, day1_value, 0.1)
      end

      # ==========================================
      # Avg Days to Convert Metric
      # ==========================================

      test "returns average days from first session to conversion" do
        day1 = 3.days.ago.to_date

        # Conversion 1: first session 4 days before conversion → 4 days
        session1 = create_session(started_at: day1.to_datetime - 4.days)
        c1 = create_conversion(converted_at: day1.to_datetime, journey_session_ids: [ session1.id ])
        create_credit_for_conversion(c1, channel: Channels::PAID_SEARCH, credit: 1.0)

        # Conversion 2: first session 2 days before conversion → 2 days
        session2 = create_session(started_at: day1.to_datetime - 2.days)
        c2 = create_conversion(converted_at: day1.to_datetime, journey_session_ids: [ session2.id ])
        create_credit_for_conversion(c2, channel: Channels::PAID_SEARCH, credit: 1.0)

        result = query(metric: DashboardMetrics::AVG_DAYS).call

        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        day1_value = day_value(paid_search, day1, result[:dates])

        # Average of 4 and 2 = 3.0
        assert_in_delta(3.0, day1_value, 0.1)
      end

      test "avg_days uses earliest session from journey_session_ids" do
        day1 = 3.days.ago.to_date

        # Two sessions: 5 days ago and 1 day ago → first touch is 5 days
        early_session = create_session(started_at: day1.to_datetime - 5.days)
        late_session = create_session(started_at: day1.to_datetime - 1.day)

        c1 = create_conversion(converted_at: day1.to_datetime, journey_session_ids: [ early_session.id, late_session.id ])
        create_credit_for_conversion(c1, channel: Channels::PAID_SEARCH, credit: 1.0)

        result = query(metric: DashboardMetrics::AVG_DAYS).call

        paid_search = result[:series].find { |s| s[:channel] == Channels::PAID_SEARCH }
        day1_value = day_value(paid_search, day1, result[:dates])

        assert_in_delta(5.0, day1_value, 0.1)
      end

      private

      def query(metric: nil)
        TimeSeriesQuery.new(build_scope, date_range: date_range, metric: metric)
      end

      def build_scope
        Scopes::CreditsScope.new(
          account: account,
          models: [ attribution_model ],
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

      def create_conversion(converted_at:, journey_session_ids: [])
        account.conversions.create!(
          visitor: visitors(:one),
          conversion_type: "purchase",
          converted_at: converted_at,
          journey_session_ids: journey_session_ids
        )
      end

      def create_session(started_at:)
        account.sessions.create!(
          visitor: visitors(:one),
          session_id: "sess_#{SecureRandom.hex(8)}",
          started_at: started_at,
          page_view_count: 1
        )
      end

      def day_value(series, date, dates_array)
        index = dates_array.index(date.iso8601)
        return 0.0 unless index

        series[:data][index]
      end
    end
  end
end
