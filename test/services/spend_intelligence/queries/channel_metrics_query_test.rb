# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  module Queries
    class ChannelMetricsQueryTest < ActiveSupport::TestCase
      REVENUE = 99.99

      setup do
        account.attribution_credits.delete_all
        account.conversions.delete_all
        create_credit(channel: Channels::PAID_SEARCH, revenue_credit: REVENUE)
      end

      test "returns metrics grouped by channel" do
        channels = query.call.map { |r| r[:channel] }

        assert_includes channels, Channels::PAID_SEARCH
        assert_includes channels, Channels::DISPLAY
      end

      test "calculates spend per channel" do
        expected = ad_spend_records(:paid_search_today).spend_micros +
                   ad_spend_records(:paid_search_yesterday).spend_micros

        assert_equal expected, channel_row(Channels::PAID_SEARCH)[:spend_micros]
      end

      test "calculates attributed revenue per channel" do
        assert_equal REVENUE, channel_row(Channels::PAID_SEARCH)[:attributed_revenue]
      end

      test "calculates ROAS as revenue divided by spend in units" do
        row = channel_row(Channels::PAID_SEARCH)
        expected = (REVENUE / (row[:spend_micros].to_d / AdSpendRecord::MICRO_UNIT)).round(2)

        assert_equal expected, row[:roas]
      end

      test "returns nil ROAS for channel with zero spend but has revenue" do
        result = query_with_no_spend.call
        paid_search = result.find { |r| r[:channel] == Channels::PAID_SEARCH }

        assert_nil paid_search[:roas]
      end

      test "includes impressions and clicks" do
        row = channel_row(Channels::PAID_SEARCH)

        assert_predicate row[:impressions], :positive?
        assert_predicate row[:clicks], :positive?
      end

      test "sorts by spend descending" do
        spends = query.call.map { |r| r[:spend_micros] }

        assert_equal spends.sort.reverse, spends
      end

      test "calculates blended ROAS across all channels" do
        assert_kind_of Numeric, query.blended_roas
        assert_predicate query.blended_roas, :positive?
      end

      test "returns nil blended ROAS when total spend is zero" do
        assert_nil query_with_no_spend.blended_roas
      end

      test "exposes total spend micros" do
        expected = ad_spend_records(:paid_search_today).spend_micros +
                   ad_spend_records(:paid_search_yesterday).spend_micros +
                   ad_spend_records(:display_today).spend_micros

        assert_equal expected, query.total_spend_micros
      end

      test "exposes total revenue" do
        assert_equal REVENUE, query.total_revenue
      end

      private

      def query
        @query ||= ChannelMetricsQuery.new(spend_scope: spend_scope, credits_scope: credits_scope)
      end

      def query_with_no_spend
        @query_with_no_spend ||= ChannelMetricsQuery.new(
          spend_scope: account.ad_spend_records.none,
          credits_scope: credits_scope
        )
      end

      def channel_row(channel)
        query.call.find { |r| r[:channel] == channel }
      end

      def spend_scope
        @spend_scope ||= Scopes::SpendScope.new(
          account: account,
          date_range: Date.yesterday..Date.current
        ).call
      end

      def credits_scope
        @credits_scope ||= Dashboard::Scopes::CreditsScope.new(
          account: account,
          models: [ attribution_model ],
          date_range: date_range,
          test_mode: false
        ).call
      end

      def create_credit(channel:, revenue_credit:)
        conversion = account.conversions.create!(
          visitor: visitors(:one),
          conversion_type: "purchase",
          revenue: revenue_credit,
          converted_at: 1.day.ago
        )
        account.attribution_credits.create!(
          conversion: conversion,
          session_id: 1,
          attribution_model: attribution_model,
          channel: channel,
          credit: 1.0,
          revenue_credit: revenue_credit,
          is_test: false
        )
      end

      def account = @account ||= accounts(:one)
      def attribution_model = @attribution_model ||= attribution_models(:last_touch)
      def date_range = @date_range ||= Dashboard::DateRangeParser.new("30d")
    end
  end
end
