# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  module Queries
    class BreakdownsQueryTest < ActiveSupport::TestCase
      test "by_hour returns 24-hour distribution" do
        hours = query.by_hour.map { |h| h[:hour] }

        assert_includes hours, 14 # fixture spend_hour
      end

      test "by_hour applies timezone offset" do
        offset_query = query(timezone_offset: 11)
        result = offset_query.by_hour
        shifted_hour = result.find { |h| h[:hour] == 1 } # 14 UTC + 11 = 25 → 1 (next day)

        assert shifted_hour, "Expected hour 1 (14 UTC + 11 offset, wrapped)"
        assert_predicate shifted_hour[:spend_micros], :positive?
      end

      test "by_hour without offset uses raw hours" do
        result = query.by_hour
        hour_14 = result.find { |h| h[:hour] == 14 }

        assert hour_14
        assert_predicate hour_14[:spend_micros], :positive?
      end

      test "by_device groups by device type" do
        devices = query.by_device.map { |d| d[:device] }

        assert_includes devices, "DESKTOP"
      end

      test "time_series returns daily entries" do
        dates = query.time_series.map { |t| t[:date] }

        assert_includes dates, Date.current.to_s
      end

      test "time_series aligns spend and revenue across midnight UTC for non-UTC report timezone" do
        account.attribution_credits.delete_all
        account.conversions.delete_all
        account.ad_spend_records.delete_all

        AdSpendRecord.create!(
          account: account,
          ad_platform_connection: ad_platform_connections(:google_ads),
          spend_date: Date.new(2026, 4, 15),
          spend_hour: 14,
          channel: Channels::PAID_SEARCH,
          platform_campaign_id: "tz_test",
          campaign_name: "TZ Test",
          campaign_type: "SEARCH",
          device: "DESKTOP",
          spend_micros: 10_000_000,
          currency: "USD",
          impressions: 100,
          clicks: 10,
          platform_conversions_micros: 0,
          platform_conversion_value_micros: 0,
          is_test: false
        )

        # Conversion at 02:00 UTC on April 16 == 19:00 PT on April 15.
        # Without TZ-aware date grouping, DATE(converted_at) returns April 16
        # in UTC and never matches the spend_date of April 15.
        conversion = account.conversions.create!(
          visitor: visitors(:one),
          conversion_type: "purchase",
          revenue: 50.0,
          converted_at: Time.utc(2026, 4, 16, 2, 0, 0)
        )
        account.attribution_credits.create!(
          conversion: conversion,
          session_id: 1,
          attribution_model: attribution_model,
          channel: Channels::PAID_SEARCH,
          credit: 1.0,
          revenue_credit: 50.0,
          is_test: false
        )

        tz_range = Date.new(2026, 4, 14)..Date.new(2026, 4, 16)
        tz_query = BreakdownsQuery.new(
          spend_scope: SpendIntelligence::Scopes::SpendScope.new(
            account: account,
            date_range: tz_range
          ).call,
          credits_scope: Dashboard::Scopes::CreditsScope.new(
            account: account,
            models: [ attribution_model ],
            date_range: Dashboard::DateRangeParser.new(
              start_date: "2026-04-14",
              end_date: "2026-04-16"
            ),
            test_mode: false
          ).call,
          timezone: "America/Los_Angeles"
        )

        april_15 = tz_query.time_series.find { |e| e[:date] == "2026-04-15" } || {}

        assert_equal [ true, true, true ],
          [ april_15[:spend_micros]&.positive?, april_15[:revenue]&.positive?, !april_15[:roas].nil? ],
          "expected April 15 entry with aligned spend + revenue + roas, got #{april_15.inspect}"
      end

      test "time_series in accrual mode dates revenue by touchpoint session, not conversion" do
        account.attribution_credits.delete_all
        account.conversions.delete_all
        account.ad_spend_records.delete_all

        # Touchpoint on April 14 22:00 UTC == April 14 15:00 PT
        # Conversion on April 16 02:00 UTC == April 15 19:00 PT (one day later in PT)
        touchpoint = account.sessions.create!(
          visitor: visitors(:one),
          session_id: "tp-accrual-1",
          started_at: Time.utc(2026, 4, 14, 22, 0, 0)
        )
        conversion = account.conversions.create!(
          visitor: visitors(:one),
          conversion_type: "purchase",
          revenue: 100.0,
          converted_at: Time.utc(2026, 4, 16, 2, 0, 0)
        )
        account.attribution_credits.create!(
          conversion: conversion,
          session_id: touchpoint.id,
          attribution_model: attribution_model,
          channel: Channels::PAID_SEARCH,
          credit: 1.0,
          revenue_credit: 100.0,
          is_test: false
        )

        accrual_query = BreakdownsQuery.new(
          spend_scope: account.ad_spend_records.none,
          credits_scope: Dashboard::Scopes::CreditsScope.new(
            account: account,
            models: [ attribution_model ],
            date_range: Dashboard::DateRangeParser.new(
              start_date: "2026-04-13",
              end_date: "2026-04-16"
            ),
            test_mode: false
          ).call,
          timezone: "America/Los_Angeles",
          accounting_mode: :accrual
        )

        ts = accrual_query.time_series
        revenue_by_date = ts.to_h { |e| [ e[:date], e[:revenue].to_f ] }

        assert_equal({ "2026-04-14" => 100.0 }, revenue_by_date.select { |_, v| v.positive? },
          "expected revenue on April 14 (touchpoint date in PT), got #{revenue_by_date.inspect}")
      end

      private

      def query(timezone_offset: nil)
        BreakdownsQuery.new(
          spend_scope: spend_scope,
          credits_scope: credits_scope,
          timezone_offset: timezone_offset
        )
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

      def account = @account ||= accounts(:one)
      def attribution_model = @attribution_model ||= attribution_models(:last_touch)
      def date_range = @date_range ||= Dashboard::DateRangeParser.new("30d")
    end
  end
end
