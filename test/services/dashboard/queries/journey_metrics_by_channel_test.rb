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

      test "returns avg_visits per channel" do
        # Conversion 1: 3 visits via paid_search
        conv1 = create_conversion
        create_credit(conv1, channel: Channels::PAID_SEARCH, session_id: 1)
        create_credit(conv1, channel: Channels::PAID_SEARCH, session_id: 2)
        create_credit(conv1, channel: Channels::PAID_SEARCH, session_id: 3)

        # Conversion 2: 1 visit via paid_search
        conv2 = create_conversion
        create_credit(conv2, channel: Channels::PAID_SEARCH, session_id: 4)

        result = query.avg_visits_by_channel

        # paid_search: (3 + 1) / 2 = 2.0
        assert_equal 2.0, result[Channels::PAID_SEARCH]
      end

      test "returns nil for channels with no conversions" do
        result = query.avg_channels_by_channel

        assert_empty result
      end

      test "handles multiple channels with different journey lengths" do
        # Conversion 1: paid_search (1 visit)
        conv1 = create_conversion
        create_credit(conv1, channel: Channels::PAID_SEARCH, session_id: 1)

        # Conversion 2: email with 4 visits
        conv2 = create_conversion
        create_credit(conv2, channel: Channels::EMAIL, session_id: 2)
        create_credit(conv2, channel: Channels::EMAIL, session_id: 3)
        create_credit(conv2, channel: Channels::EMAIL, session_id: 4)
        create_credit(conv2, channel: Channels::EMAIL, session_id: 5)

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

      def create_conversion
        account.conversions.create!(
          visitor: visitors(:one),
          conversion_type: "purchase",
          converted_at: 1.day.ago
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
    end
  end
end
