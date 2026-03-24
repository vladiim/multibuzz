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
