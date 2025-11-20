# frozen_string_literal: true

require "test_helper"

module Attribution
  module Algorithms
    class LinearTest < ActiveSupport::TestCase
      test "should distribute credit equally across all touchpoints" do
        credits = service.call

        assert_equal 3, credits.size

        credits.each do |credit|
          assert_in_delta 0.3333, credit[:credit], 0.0001
        end

        assert_equal "organic_search", credits[0][:channel]
        assert_equal "email", credits[1][:channel]
        assert_equal "paid_search", credits[2][:channel]
      end

      test "should handle single touchpoint journey" do
        credits = Attribution::Algorithms::Linear.new([touchpoints[0]]).call

        assert_equal 1, credits.size
        assert_equal 1.0, credits[0][:credit]
      end

      test "should handle two touchpoint journey" do
        credits = Attribution::Algorithms::Linear.new(touchpoints[0..1]).call

        assert_equal 2, credits.size
        assert_equal 0.5, credits[0][:credit]
        assert_equal 0.5, credits[1][:credit]
      end

      test "should return empty array for empty journey" do
        credits = Attribution::Algorithms::Linear.new([]).call

        assert_empty credits
      end

      test "should sum to exactly 1.0" do
        credits = service.call

        total = credits.sum { |c| c[:credit] }
        assert_in_delta 1.0, total, 0.0001
      end

      private

      def service
        @service ||= Attribution::Algorithms::Linear.new(touchpoints)
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
