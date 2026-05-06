# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  module Queries
    class PlatformVsAttributedQueryTest < ActiveSupport::TestCase
      # Fixtures: paid_search platform value = $50 + $45 = $95; display = $8.
      # Test attributes a single $99.99 credit to paid_search, leaves display uncovered.
      PAID_SEARCH_PLATFORM = 95.0
      DISPLAY_PLATFORM = 8.0
      ATTRIBUTED = 99.99

      setup do
        account.attribution_credits.delete_all
        account.conversions.delete_all
        create_credit(channel: Channels::PAID_SEARCH, revenue_credit: ATTRIBUTED)
      end

      test "exposes per-channel platform_revenue, gap, and gap_pct" do
        row = paid_search_row

        assert_in_delta PAID_SEARCH_PLATFORM, row[:platform_revenue], 0.01
        assert_in_delta(ATTRIBUTED - PAID_SEARCH_PLATFORM, row[:gap], 0.01)
        assert_in_delta(((ATTRIBUTED - PAID_SEARCH_PLATFORM) / PAID_SEARCH_PLATFORM * 100).round(1), row[:gap_pct], 0.01)
      end

      test "channel with platform value but no attributed credits has gap_pct of -100" do
        row = display_row

        assert_in_delta DISPLAY_PLATFORM, row[:platform_revenue], 0.01
        assert_in_delta(-DISPLAY_PLATFORM, row[:gap], 0.01)
        assert_in_delta(-100.0, row[:gap_pct], 0.01)
      end

      test "gap_pct is nil when platform_revenue is zero" do
        row = query_with_zero_platform.by_channel[Channels::PAID_SEARCH]

        assert_in_delta ATTRIBUTED, row[:gap], 0.01
        assert_nil row[:gap_pct]
      end

      test "totals roll up platform, gap, and gap_pct across channels" do
        totals = query.totals
        expected_platform = PAID_SEARCH_PLATFORM + DISPLAY_PLATFORM
        expected_gap = ATTRIBUTED - expected_platform

        assert_in_delta expected_platform, totals[:platform_revenue], 0.01
        assert_in_delta expected_gap, totals[:gap], 0.01
        assert_in_delta((expected_gap / expected_platform * 100).round(1), totals[:gap_pct], 0.01)
      end

      test "totals gap_pct is nil when account has no platform_revenue" do
        assert_nil query_with_zero_platform.totals[:gap_pct]
      end

      private

      def query
        @query ||= PlatformVsAttributedQuery.new(spend_scope: spend_scope, credits_scope: credits_scope)
      end

      def query_with_zero_platform
        @query_with_zero_platform ||= PlatformVsAttributedQuery.new(
          spend_scope: account.ad_spend_records.none,
          credits_scope: credits_scope
        )
      end

      def paid_search_row = query.by_channel[Channels::PAID_SEARCH]
      def display_row = query.by_channel[Channels::DISPLAY]

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
