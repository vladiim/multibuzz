# frozen_string_literal: true

require "test_helper"

module Attribution
  module Algorithms
    class FirstTouchTest < ActiveSupport::TestCase
      test "should assign 100% credit to first touchpoint" do
        credits = service.call

        assert_equal 1, credits.size
        assert_equal "organic_search", credits[0][:channel]
        assert_equal 1.0, credits[0][:credit]
        assert_equal session_ids[0], credits[0][:session_id]
      end

      test "should handle single touchpoint journey" do
        credits = Attribution::Algorithms::FirstTouch.new([touchpoints[0]]).call

        assert_equal 1, credits.size
        assert_equal 1.0, credits[0][:credit]
      end

      test "should return empty array for empty journey" do
        credits = Attribution::Algorithms::FirstTouch.new([]).call

        assert_empty credits
      end

      private

      def service
        @service ||= Attribution::Algorithms::FirstTouch.new(touchpoints)
      end

      def touchpoints
        @touchpoints ||= [
          {
            session_id: session_ids[0],
            channel: "organic_search",
            occurred_at: 5.days.ago
          },
          {
            session_id: session_ids[1],
            channel: "email",
            occurred_at: 2.days.ago
          },
          {
            session_id: session_ids[2],
            channel: "paid_search",
            occurred_at: 1.hour.ago
          }
        ]
      end

      def session_ids
        @session_ids ||= [100, 101, 102]
      end
    end
  end
end
