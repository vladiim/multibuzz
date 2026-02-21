# frozen_string_literal: true

require "test_helper"

module DataIntegrity
  module Checks
    class EventVolumeTest < ActiveSupport::TestCase
      setup do
        account.events.destroy_all
      end

      test "returns healthy when volume stable" do
        create_events(count: 100, period: :previous)
        create_events(count: 95, period: :current)

        result = check.call

        assert_equal :healthy, result[:status]
      end

      test "returns warning on significant drop" do
        create_events(count: 100, period: :previous)
        create_events(count: 60, period: :current)

        result = check.call

        assert_equal :warning, result[:status]
        assert_in_delta(-40.0, result[:value])
      end

      test "returns critical on severe drop" do
        create_events(count: 100, period: :previous)
        create_events(count: 30, period: :current)

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta(-70.0, result[:value])
      end

      test "returns warning on significant spike" do
        create_events(count: 100, period: :previous)
        create_events(count: 350, period: :current)

        result = check.call

        assert_equal :warning, result[:status]
        assert_in_delta 250.0, result[:value]
      end

      test "returns critical on severe spike" do
        create_events(count: 100, period: :previous)
        create_events(count: 650, period: :current)

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta 550.0, result[:value]
      end

      test "returns healthy with zero events in both periods" do
        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "returns critical when previous period empty but current has events" do
        create_events(count: 50, period: :current)

        result = check.call

        assert_equal :critical, result[:status]
      end

      test "returns critical when current period empty but previous had events" do
        create_events(count: 50, period: :previous)

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta(-100.0, result[:value])
      end

      test "returns correct check metadata" do
        result = check.call

        assert_equal "event_volume", result[:check_name]
      end

      private

      def account = @account ||= accounts(:one)
      def visitor = @visitor ||= visitors(:one)
      def session = @session ||= sessions(:one)
      def check = DataIntegrity::Checks::EventVolume.new(account)

      def create_events(count:, period:)
        time = period == :current ? 12.hours.ago : 36.hours.ago
        count.times do
          account.events.create!(
            visitor: visitor,
            session: session,
            event_type: "page_view",
            occurred_at: time + rand(60).minutes,
            properties: { url: "https://example.com" }
          )
        end
      end
    end
  end
end
