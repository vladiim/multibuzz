# frozen_string_literal: true

require "test_helper"

module Attribution
  module Algorithms
    class WShapedTest < ActiveSupport::TestCase
      test "should give 30% to first, middle, and last with 10% split among others" do
        credits = service.call

        assert_equal 5, credits.size
        assert_equal 0.3, credits[0][:credit]    # first (key)
        assert_equal 0.05, credits[1][:credit]   # other (10% / 2)
        assert_equal 0.3, credits[2][:credit]    # middle (key)
        assert_equal 0.05, credits[3][:credit]   # other (10% / 2)
        assert_equal 0.3, credits[4][:credit]    # last (key)
      end

      test "should handle single touchpoint journey" do
        credits = Attribution::Algorithms::WShaped.new([touchpoints[0]]).call

        assert_equal 1, credits.size
        assert_equal 1.0, credits[0][:credit]
      end

      test "should handle two touchpoint journey with 50/50 split" do
        credits = Attribution::Algorithms::WShaped.new(touchpoints[0..1]).call

        assert_equal 2, credits.size
        assert_equal 0.5, credits[0][:credit]
        assert_equal 0.5, credits[1][:credit]
      end

      test "should handle three touchpoint journey with equal split" do
        three_touchpoints = touchpoints[0..2]
        credits = Attribution::Algorithms::WShaped.new(three_touchpoints).call

        assert_equal 3, credits.size
        credits.each do |credit|
          assert_in_delta 0.3333, credit[:credit], 0.0001
        end
      end

      test "should handle four touchpoint journey" do
        four_touchpoints = touchpoints[0..3]
        credits = Attribution::Algorithms::WShaped.new(four_touchpoints).call

        assert_equal 4, credits.size
        assert_equal 0.3, credits[0][:credit]   # first (key)
        assert_equal 0.1, credits[1][:credit]   # other (all 10%)
        assert_equal 0.3, credits[2][:credit]   # middle (key)
        assert_equal 0.3, credits[3][:credit]   # last (key)
      end

      test "should return empty array for empty journey" do
        credits = Attribution::Algorithms::WShaped.new([]).call

        assert_empty credits
      end

      test "should sum to exactly 1.0" do
        credits = service.call

        total = credits.sum { |c| c[:credit] }
        assert_in_delta 1.0, total, 0.0001
      end

      test "should preserve channel information" do
        credits = service.call

        assert_equal "organic_search", credits[0][:channel]
        assert_equal "email", credits[1][:channel]
        assert_equal "paid_social", credits[2][:channel]
        assert_equal "referral", credits[3][:channel]
        assert_equal "paid_search", credits[4][:channel]
      end

      test "should handle many touchpoints" do
        many_touchpoints = (0..9).map do |i|
          { session_id: i, channel: "channel_#{i}", occurred_at: (10 - i).days.ago }
        end
        credits = Attribution::Algorithms::WShaped.new(many_touchpoints).call

        assert_equal 10, credits.size
        assert_equal 0.3, credits[0][:credit]   # first (key)
        assert_equal 0.3, credits[5][:credit]   # middle (key) - index 10/2 = 5
        assert_equal 0.3, credits[9][:credit]   # last (key)

        # 7 "others" split 10%
        other_indices = [1, 2, 3, 4, 6, 7, 8]
        other_indices.each do |i|
          assert_in_delta 0.01428, credits[i][:credit], 0.0001  # 0.1 / 7
        end
      end

      private

      def service
        @service ||= Attribution::Algorithms::WShaped.new(touchpoints)
      end

      def touchpoints
        @touchpoints ||= [
          { session_id: 100, channel: "organic_search", occurred_at: 10.days.ago },
          { session_id: 101, channel: "email", occurred_at: 7.days.ago },
          { session_id: 102, channel: "paid_social", occurred_at: 5.days.ago },
          { session_id: 103, channel: "referral", occurred_at: 2.days.ago },
          { session_id: 104, channel: "paid_search", occurred_at: 1.hour.ago }
        ]
      end
    end
  end
end
