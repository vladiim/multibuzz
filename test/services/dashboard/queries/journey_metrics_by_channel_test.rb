# frozen_string_literal: true

require "test_helper"

module Dashboard
  module Queries
    class JourneyMetricsByChannelTest < ActiveSupport::TestCase
      setup do
        AttributionCredit.delete_all
        Conversion.where(account: account).delete_all
      end

      test "returns avg_channels per channel" do
        # Conversion 1: paid_search + email (2 channels)
        conv1 = create_conversion
        create_credit(conv1, channel: Channels::PAID_SEARCH, session_id: 1)
        create_credit(conv1, channel: Channels::EMAIL, session_id: 2)

        # Conversion 2: paid_search only (1 channel)
        conv2 = create_conversion
        create_credit(conv2, channel: Channels::PAID_SEARCH, session_id: 3)

        result = query.avg_channels_by_channel

        # paid_search appears in both conversions: (2 + 1) / 2 = 1.5
        assert_equal 1.5, result[Channels::PAID_SEARCH]
        # email appears in 1 conversion with 2 channels: 2 / 1 = 2.0
        assert_equal 2.0, result[Channels::EMAIL]
      end

      test "returns avg_visits per channel based on journey_session_ids" do
        # Conversion 1: 3 visits in journey, via paid_search
        s1, s2, s3 = create_sessions(3)
        conv1 = create_conversion(journey_session_ids: [s1.id, s2.id, s3.id])
        create_credit(conv1, channel: Channels::PAID_SEARCH, session_id: s1.id)

        # Conversion 2: 1 visit in journey, via paid_search
        s4 = create_session
        conv2 = create_conversion(journey_session_ids: [s4.id])
        create_credit(conv2, channel: Channels::PAID_SEARCH, session_id: s4.id)

        result = query.avg_visits_by_channel

        # paid_search: (3 + 1) / 2 = 2.0 (journey lengths, not credit counts)
        assert_equal 2.0, result[Channels::PAID_SEARCH]
      end

      test "returns nil for channels with no conversions" do
        result = query.avg_channels_by_channel

        assert_empty result
      end

      test "handles multiple channels with different journey lengths" do
        # Conversion 1: paid_search (1 visit in journey)
        s1 = create_session
        conv1 = create_conversion(journey_session_ids: [s1.id])
        create_credit(conv1, channel: Channels::PAID_SEARCH, session_id: s1.id)

        # Conversion 2: email with 4 visits in journey
        s2, s3, s4, s5 = create_sessions(4)
        conv2 = create_conversion(journey_session_ids: [s2.id, s3.id, s4.id, s5.id])
        create_credit(conv2, channel: Channels::EMAIL, session_id: s2.id)

        result = query.avg_visits_by_channel

        assert_equal 1.0, result[Channels::PAID_SEARCH]
        assert_equal 4.0, result[Channels::EMAIL]
      end

      private

      def query
        JourneyMetricsByChannel.new(build_scope)
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

      def create_conversion(journey_session_ids: [])
        account.conversions.create!(
          visitor: visitors(:one),
          conversion_type: "purchase",
          converted_at: 1.day.ago,
          journey_session_ids: journey_session_ids
        )
      end

      def create_credit(conversion, channel:, session_id:)
        account.attribution_credits.create!(
          conversion: conversion,
          attribution_model: attribution_model,
          session_id: session_id,
          channel: channel,
          credit: 0.5,
          is_test: false
        )
      end

      def create_session
        account.sessions.create!(
          visitor: visitors(:one),
          session_id: "sess_#{SecureRandom.hex(8)}",
          started_at: rand(1..30).days.ago
        )
      end

      def create_sessions(count)
        count.times.map { create_session }
      end
    end
  end
end
