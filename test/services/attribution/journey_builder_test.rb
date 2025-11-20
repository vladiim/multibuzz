# frozen_string_literal: true

require "test_helper"

module Attribution
  class JourneyBuilderTest < ActiveSupport::TestCase
    test "should build journey from sessions within lookback window" do
      session_one
      session_two

      touchpoints = service.call

      assert_equal 2, touchpoints.size
      assert_equal session_one.id, touchpoints[0][:session_id]
      assert_equal session_two.id, touchpoints[1][:session_id]
    end

    test "should extract channel from each session" do
      session_one
      session_two

      touchpoints = service.call

      assert_equal "organic_search", touchpoints[0][:channel]
      assert_equal "email", touchpoints[1][:channel]
    end

    test "should order touchpoints by session started_at ascending" do
      session_one
      session_two

      touchpoints = service.call

      assert touchpoints[0][:occurred_at] < touchpoints[1][:occurred_at]
      assert_equal session_one.started_at, touchpoints[0][:occurred_at]
      assert_equal session_two.started_at, touchpoints[1][:occurred_at]
    end

    test "should only include channel data for attribution algorithms" do
      session_one
      session_two

      touchpoints = service.call

      # Algorithms only need session_id, channel, occurred_at
      assert_equal [:channel, :occurred_at, :session_id], touchpoints[0].keys.sort
      assert_not touchpoints[0].key?(:utm_source)
      assert_not touchpoints[0].key?(:utm_medium)
      assert_not touchpoints[0].key?(:utm_campaign)
    end

    test "should exclude sessions outside lookback window" do
      session_one
      session_two
      old_session = build_session(days_ago: 45, channel: "paid_search")

      touchpoints = service.call

      assert_equal 2, touchpoints.size
      assert_not touchpoints.any? { |t| t[:session_id] == old_session.id }
    end

    test "should handle visitor with no sessions" do
      empty_visitor = visitors(:other_account_visitor)
      empty_service = build_service(visitor: empty_visitor)

      touchpoints = empty_service.call

      assert_empty touchpoints
    end

    test "should use default 30 day lookback window" do
      session_29_days = build_session(days_ago: 29, channel: "paid_social")
      session_31_days = build_session(days_ago: 31, channel: "display")

      touchpoints = service.call

      session_ids = touchpoints.map { |t| t[:session_id] }
      assert_includes session_ids, session_29_days.id
      assert_not_includes session_ids, session_31_days.id
    end

    test "should support custom lookback window" do
      custom_service = build_service(lookback_days: 7)

      session_6_days = build_session(days_ago: 6, channel: "video")
      session_8_days = build_session(days_ago: 8, channel: "affiliate")

      touchpoints = custom_service.call

      session_ids = touchpoints.map { |t| t[:session_id] }
      assert_includes session_ids, session_6_days.id
      assert_not_includes session_ids, session_8_days.id
    end

    test "should handle sessions with missing channel" do
      session_no_channel = build_session(days_ago: 5, channel: nil)

      touchpoints = service.call

      # Should skip sessions without channel classification
      assert_not touchpoints.any? { |t| t[:session_id] == session_no_channel.id }
    end

    private

    def service
      @service ||= build_service
    end

    def build_service(visitor: default_visitor, converted_at: Time.current, lookback_days: 30)
      Attribution::JourneyBuilder.new(
        visitor: visitor,
        converted_at: converted_at,
        lookback_days: lookback_days
      )
    end

    def session_one
      @session_one ||= build_session(
        days_ago: 10,
        channel: "organic_search",
        utm_source: "google",
        utm_medium: "organic"
      )
    end

    def session_two
      @session_two ||= build_session(
        days_ago: 3,
        channel: "email",
        utm_source: "newsletter",
        utm_medium: "email",
        utm_campaign: "weekly"
      )
    end

    def build_session(days_ago:, channel:, utm_source: nil, utm_medium: nil, utm_campaign: nil)
      utm_data = {}
      utm_data["utm_source"] = utm_source if utm_source
      utm_data["utm_medium"] = utm_medium if utm_medium
      utm_data["utm_campaign"] = utm_campaign if utm_campaign

      Session.create!(
        account: default_visitor.account,
        visitor: default_visitor,
        session_id: SecureRandom.hex(16),
        started_at: days_ago.days.ago,
        channel: channel,
        initial_utm: utm_data
      )
    end

    def default_visitor
      @default_visitor ||= visitors(:one)
    end
  end
end
