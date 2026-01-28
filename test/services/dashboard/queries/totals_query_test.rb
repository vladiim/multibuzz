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

        assert_equal 1.0, result[:conversions]
      end

      test "returns revenue as sum of revenue_credit" do
        create_credit(credit: 0.5, revenue_credit: 50.0)
        create_credit(credit: 0.5, revenue_credit: 100.0)

        assert_equal 150.0, result[:revenue]
      end

      test "returns aov as revenue divided by conversions" do
        create_credit(credit: 0.5, revenue_credit: 50.0)
        create_credit(credit: 0.5, revenue_credit: 50.0)

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

        # Average: (2 + 3) / 2 = 2.5
        assert_equal 2.5, result[:avg_channels_to_convert]
      end

      test "returns avg_visits_to_convert based on journey_session_ids count" do
        # Conversion 1: 2 sessions in journey
        s1, s2 = create_sessions(2)
        conv1 = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: [s1.id, s2.id]
        )
        create_credit_for_conversion(conv1)

        # Conversion 2: 4 sessions in journey
        s3, s4, s5, s6 = create_sessions(4)
        conv2 = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: [s3.id, s4.id, s5.id, s6.id]
        )
        create_credit_for_conversion(conv2)

        # Average: (2 + 4) / 2 = 3.0 based on journey length, NOT credit count
        assert_equal 3.0, result[:avg_visits_to_convert]
      end

      test "avg_visits is independent of attribution model credit count" do
        # Create a conversion with 5 sessions in journey
        sessions = create_sessions(5)
        conversion = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: sessions.map(&:id)
        )

        # First Touch creates 1 credit, but journey has 5 sessions
        create_credit_for_conversion(conversion)

        # Should return 5.0 (journey length), not 1.0 (credit count)
        assert_equal 5.0, result[:avg_visits_to_convert]
      end

      test "avg_visits skips conversions with empty journey" do
        # Conversion 1: 3 sessions
        sessions = create_sessions(3)
        conv1 = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: sessions.map(&:id)
        )
        create_credit_for_conversion(conv1)

        # Conversion 2: empty journey (should be skipped)
        conv2 = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: []
        )
        create_credit_for_conversion(conv2)

        # Should return 3.0 (only conv1 counted)
        assert_equal 3.0, result[:avg_visits_to_convert]
      end

      test "handles empty data gracefully" do
        assert_equal 0, result[:conversions]
        assert_equal 0, result[:revenue]
        assert_nil result[:aov]
        assert_nil result[:avg_channels_to_convert]
        assert_nil result[:avg_visits_to_convert]
        assert_nil result[:avg_days_to_convert]
      end

      test "returns avg_days_to_convert for single conversion" do
        # Session started 5 days before conversion
        session = create_session(started_at: 5.days.ago)
        conversion = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: [session.id]
        )
        create_credit_for_conversion(conversion)

        assert_in_delta 5.0, result[:avg_days_to_convert], 0.1
      end

      test "returns avg_days_to_convert averaged across multiple conversions" do
        # Conversion 1: 3 days to convert
        session1 = create_session(started_at: 3.days.ago)
        conv1 = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: [session1.id]
        )
        create_credit_for_conversion(conv1)

        # Conversion 2: 7 days to convert
        session2 = create_session(started_at: 7.days.ago)
        conv2 = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: [session2.id]
        )
        create_credit_for_conversion(conv2)

        # Average: (3 + 7) / 2 = 5.0
        assert_in_delta 5.0, result[:avg_days_to_convert], 0.1
      end

      test "uses earliest session for multi-session journey" do
        # Journey: session 10 days ago, then 5 days ago, then 1 day ago
        session_first = create_session(started_at: 10.days.ago)
        session_second = create_session(started_at: 5.days.ago)
        session_third = create_session(started_at: 1.day.ago)

        conversion = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: [session_first.id, session_second.id, session_third.id]
        )
        create_credit_for_conversion(conversion)

        # Should use first session (10 days ago)
        assert_in_delta 10.0, result[:avg_days_to_convert], 0.1
      end

      test "returns zero for same-session conversion" do
        now = Time.current
        session = create_session(started_at: now)
        conversion = create_conversion_with_journey(
          converted_at: now,
          journey_session_ids: [session.id]
        )
        create_credit_for_conversion(conversion)

        assert_in_delta 0.0, result[:avg_days_to_convert], 0.01
      end

      test "skips conversions with empty journey_session_ids" do
        # Conversion 1: Has valid journey (5 days)
        session = create_session(started_at: 5.days.ago)
        conv1 = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: [session.id]
        )
        create_credit_for_conversion(conv1)

        # Conversion 2: Empty journey (should be skipped)
        conv2 = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: []
        )
        create_credit_for_conversion(conv2)

        # Should only use conversion 1
        assert_in_delta 5.0, result[:avg_days_to_convert], 0.1
      end

      test "includes both acquisition and non-acquisition conversions in avg_days" do
        # Acquisition: 10-day journey
        acquisition_session = create_session(started_at: 10.days.ago)
        acquisition = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: [acquisition_session.id],
          is_acquisition: true
        )
        create_credit_for_conversion(acquisition)

        # Non-acquisition: 2-day journey
        repeat_session = create_session(started_at: 2.days.ago)
        repeat = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: [repeat_session.id]
        )
        create_credit_for_conversion(repeat)

        # Median of [2, 10] = 6.0
        assert_in_delta 6.0, result[:avg_days_to_convert], 0.5
      end

      # Median-based calculation tests (resistant to outliers)

      test "uses median for avg_visits_to_convert to resist outliers" do
        # Create 5 normal conversions with 1-2 sessions each
        4.times do
          s = create_session(started_at: 1.day.ago)
          conv = create_conversion_with_journey(
            converted_at: Time.current,
            journey_session_ids: [s.id]
          )
          create_credit_for_conversion(conv)
        end

        # Create 1 outlier with 100 sessions
        outlier_sessions = create_sessions(100)
        outlier = create_conversion_with_journey(
          converted_at: Time.current,
          journey_session_ids: outlier_sessions.map(&:id)
        )
        create_credit_for_conversion(outlier)

        # Median of [1, 1, 1, 1, 100] = 1 (middle value)
        # Mean would be 20.8, but median is 1
        assert_equal 1.0, result[:avg_visits_to_convert]
      end

      test "uses median for avg_days_to_convert to resist outliers" do
        now = Time.current

        # 4 conversions with 1-day journey
        4.times do
          s = create_session(started_at: 1.day.ago)
          conv = create_conversion_with_journey(
            converted_at: now,
            journey_session_ids: [s.id]
          )
          create_credit_for_conversion(conv)
        end

        # 1 outlier with 100-day journey
        outlier_session = create_session(started_at: 100.days.ago)
        outlier = create_conversion_with_journey(
          converted_at: now,
          journey_session_ids: [outlier_session.id]
        )
        create_credit_for_conversion(outlier)

        # Median of [1, 1, 1, 1, 100] = 1 (middle value)
        # Mean would be 20.8, but median is 1
        assert_in_delta 1.0, result[:avg_days_to_convert], 0.1
      end

      test "uses median for avg_channels_to_convert to resist outliers" do
        # 4 conversions with 1 channel each
        4.times do
          conv = create_conversion
          create_credit_for_conversion(conv, channel: Channels::DIRECT)
        end

        # 1 outlier with 10 channels
        outlier = create_conversion
        [
          Channels::PAID_SEARCH, Channels::ORGANIC_SEARCH, Channels::PAID_SOCIAL,
          Channels::ORGANIC_SOCIAL, Channels::EMAIL, Channels::DIRECT,
          Channels::REFERRAL, Channels::DISPLAY, Channels::VIDEO, Channels::OTHER
        ].each do |channel|
          create_credit_for_conversion(outlier, channel: channel)
        end

        # Median of [1, 1, 1, 1, 10] = 1 (middle value)
        # Mean would be 2.8, but median is 1
        assert_equal 1.0, result[:avg_channels_to_convert]
      end

      test "median with even number of elements averages two middle values" do
        # 4 conversions: 2 with 2 sessions, 2 with 4 sessions
        2.times do
          sessions = create_sessions(2)
          conv = create_conversion_with_journey(
            converted_at: Time.current,
            journey_session_ids: sessions.map(&:id)
          )
          create_credit_for_conversion(conv)
        end

        2.times do
          sessions = create_sessions(4)
          conv = create_conversion_with_journey(
            converted_at: Time.current,
            journey_session_ids: sessions.map(&:id)
          )
          create_credit_for_conversion(conv)
        end

        # Sorted: [2, 2, 4, 4] -> median = (2 + 4) / 2 = 3.0
        assert_equal 3.0, result[:avg_visits_to_convert]
      end

      private

      def result
        query.call
      end

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

      def visitor
        @visitor ||= visitors(:one)
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
          visitor: visitor,
          conversion_type: "purchase",
          converted_at: 1.day.ago
        )
      end

      def create_conversion_with_journey(converted_at:, journey_session_ids:, is_acquisition: false)
        attrs = {
          visitor: visitor,
          conversion_type: "purchase",
          converted_at: converted_at,
          journey_session_ids: journey_session_ids,
          is_acquisition: is_acquisition
        }
        attrs[:identity] = create_identity if is_acquisition
        account.conversions.create!(attrs)
      end

      def create_identity
        account.identities.create!(
          external_id: "test_#{SecureRandom.hex(8)}",
          first_identified_at: Time.current,
          last_identified_at: Time.current
        )
      end

      def create_session(started_at:)
        account.sessions.create!(
          visitor: visitor,
          session_id: "sess_#{SecureRandom.hex(8)}",
          started_at: started_at
        )
      end

      def create_sessions(count)
        count.times.map do
          create_session(started_at: rand(1..30).days.ago)
        end
      end
    end
  end
end
