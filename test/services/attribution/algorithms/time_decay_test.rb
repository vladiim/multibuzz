# frozen_string_literal: true

require "test_helper"

module Attribution
  module Algorithms
    class TimeDecayTest < ActiveSupport::TestCase
      test "should give more credit to recent touchpoints" do
        credits = service.call

        assert_equal 3, credits.size

        # Most recent (at conversion) should get most credit
        # Oldest (14 days ago) should get least credit
        assert credits[2][:credit] > credits[1][:credit]
        assert credits[1][:credit] > credits[0][:credit]
      end

      test "should apply correct decay formula with 7-day half-life" do
        # With 7-day half-life:
        # - touchpoint at conversion (0 days): weight = 2^0 = 1.0
        # - touchpoint 7 days before: weight = 2^(-1) = 0.5
        # - touchpoint 14 days before: weight = 2^(-2) = 0.25
        credits = service.call

        # Total weight = 1.0 + 0.5 + 0.25 = 1.75
        # Credits: 0.25/1.75 = 0.1429, 0.5/1.75 = 0.2857, 1.0/1.75 = 0.5714
        assert_in_delta 0.1429, credits[0][:credit], 0.01
        assert_in_delta 0.2857, credits[1][:credit], 0.01
        assert_in_delta 0.5714, credits[2][:credit], 0.01
      end

      test "should handle single touchpoint journey" do
        credits = Attribution::Algorithms::TimeDecay.new([touchpoints[0]]).call

        assert_equal 1, credits.size
        assert_equal 1.0, credits[0][:credit]
      end

      test "should handle two touchpoint journey" do
        two_touchpoints = [
          { session_id: 100, channel: "organic_search", occurred_at: 7.days.ago },
          { session_id: 101, channel: "email", occurred_at: Time.current }
        ]
        credits = Attribution::Algorithms::TimeDecay.new(two_touchpoints).call

        assert_equal 2, credits.size
        # 7 days = half-life, so first gets 1/3, second gets 2/3
        assert_in_delta 0.3333, credits[0][:credit], 0.01
        assert_in_delta 0.6667, credits[1][:credit], 0.01
      end

      test "should return empty array for empty journey" do
        credits = Attribution::Algorithms::TimeDecay.new([]).call

        assert_empty credits
      end

      test "should sum to exactly 1.0" do
        credits = service.call

        total = credits.sum { |c| c[:credit] }
        assert_in_delta 1.0, total, 0.0001
      end

      test "should support custom half-life" do
        two_touchpoints = [
          { session_id: 100, channel: "organic_search", occurred_at: 14.days.ago },
          { session_id: 101, channel: "email", occurred_at: Time.current }
        ]

        default_credits = Attribution::Algorithms::TimeDecay.new(two_touchpoints).call
        custom_credits = Attribution::Algorithms::TimeDecay.new(
          two_touchpoints,
          half_life_days: 14
        ).call

        # With longer half-life, older touchpoint gets more credit
        assert custom_credits[0][:credit] > default_credits[0][:credit]
      end

      test "should handle touchpoints on same day equally" do
        same_day_touchpoints = [
          { session_id: 100, channel: "organic_search", occurred_at: Time.current },
          { session_id: 101, channel: "email", occurred_at: Time.current },
          { session_id: 102, channel: "paid_search", occurred_at: Time.current }
        ]
        credits = Attribution::Algorithms::TimeDecay.new(same_day_touchpoints).call

        assert_equal 3, credits.size
        credits.each do |credit|
          assert_in_delta 0.3333, credit[:credit], 0.0001
        end
      end

      private

      def service
        @service ||= Attribution::Algorithms::TimeDecay.new(touchpoints)
      end

      def touchpoints
        @touchpoints ||= [
          {
            session_id: session_ids[0],
            channel: "organic_search",
            occurred_at: 14.days.ago
          },
          {
            session_id: session_ids[1],
            channel: "email",
            occurred_at: 7.days.ago
          },
          {
            session_id: session_ids[2],
            channel: "paid_search",
            occurred_at: Time.current
          }
        ]
      end

      def session_ids
        @session_ids ||= [100, 101, 102]
      end
    end
  end
end
