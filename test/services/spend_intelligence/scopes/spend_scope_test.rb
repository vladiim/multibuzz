# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  module Scopes
    class SpendScopeTest < ActiveSupport::TestCase
      test "returns records within date range" do
        result = scope(date_range: Date.current..Date.current).call

        assert result.all? { |r| r.spend_date == Date.current }
      end

      test "excludes records outside date range" do
        result = scope(date_range: 1.week.ago.to_date..2.days.ago.to_date).call

        assert_empty result
      end

      test "filters by channel" do
        result = scope(channels: [ Channels::DISPLAY ]).call

        assert result.all? { |r| r.channel == Channels::DISPLAY }
      end

      test "returns all channels when channels is ALL" do
        result = scope(channels: Channels::ALL).call

        assert_operator result.pluck(:channel).uniq.size, :>, 1
      end

      test "filters by device" do
        result = scope(devices: "DESKTOP").call

        assert result.all? { |r| r.device == "DESKTOP" }
      end

      test "filters by hour" do
        result = scope(hours: 14).call

        assert result.all? { |r| r.spend_hour == 14 }
      end

      test "excludes test records by default" do
        result = scope.call

        assert result.none?(&:is_test)
      end

      test "returns only test records in test mode" do
        result = scope(test_mode: true).call

        assert result.all?(&:is_test)
      end

      test "scopes to account" do
        result = scope.call

        assert result.all? { |r| r.account_id == account.id }
      end

      private

      def scope(date_range: Date.yesterday..Date.current, channels: Channels::ALL, devices: nil, hours: nil, test_mode: false)
        SpendScope.new(
          account: account,
          date_range: date_range,
          channels: channels,
          devices: devices,
          hours: hours,
          test_mode: test_mode
        )
      end

      def account = @account ||= accounts(:one)
    end
  end
end
