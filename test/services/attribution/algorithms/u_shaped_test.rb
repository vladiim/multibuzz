# frozen_string_literal: true

require "test_helper"

module Attribution
  module Algorithms
    class UShapedTest < ActiveSupport::TestCase
      test "should give 40% to first, 40% to last, 20% split among middle" do
        credits = service.call

        assert_equal 4, credits.size
        assert_equal 0.4, credits[0][:credit]   # first
        assert_equal 0.1, credits[1][:credit]   # middle (20% / 2)
        assert_equal 0.1, credits[2][:credit]   # middle (20% / 2)
        assert_equal 0.4, credits[3][:credit]   # last
      end

      test "should handle single touchpoint journey" do
        credits = Attribution::Algorithms::UShaped.new([touchpoints[0]]).call

        assert_equal 1, credits.size
        assert_equal 1.0, credits[0][:credit]
      end

      test "should handle two touchpoint journey with 50/50 split" do
        credits = Attribution::Algorithms::UShaped.new(touchpoints[0..1]).call

        assert_equal 2, credits.size
        assert_equal 0.5, credits[0][:credit]
        assert_equal 0.5, credits[1][:credit]
      end

      test "should handle three touchpoint journey" do
        three_touchpoints = touchpoints[0..2]
        credits = Attribution::Algorithms::UShaped.new(three_touchpoints).call

        assert_equal 3, credits.size
        assert_equal 0.4, credits[0][:credit]   # first
        assert_equal 0.2, credits[1][:credit]   # middle (all 20%)
        assert_equal 0.4, credits[2][:credit]   # last
      end

      test "should return empty array for empty journey" do
        credits = Attribution::Algorithms::UShaped.new([]).call

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
        assert_equal "paid_search", credits[3][:channel]
      end

      test "should handle many middle touchpoints" do
        many_touchpoints = (0..9).map do |i|
          { session_id: i, channel: "channel_#{i}", occurred_at: (10 - i).days.ago }
        end
        credits = Attribution::Algorithms::UShaped.new(many_touchpoints).call

        assert_equal 10, credits.size
        assert_equal 0.4, credits.first[:credit]
        assert_equal 0.4, credits.last[:credit]

        middle_credits = credits[1..-2]
        middle_credits.each do |credit|
          assert_in_delta 0.025, credit[:credit], 0.0001  # 0.2 / 8
        end
      end

      private

      def service
        @service ||= Attribution::Algorithms::UShaped.new(touchpoints)
      end

      def touchpoints
        @touchpoints ||= [
          { session_id: 100, channel: "organic_search", occurred_at: 10.days.ago },
          { session_id: 101, channel: "email", occurred_at: 5.days.ago },
          { session_id: 102, channel: "paid_social", occurred_at: 2.days.ago },
          { session_id: 103, channel: "paid_search", occurred_at: 1.hour.ago }
        ]
      end
    end
  end
end
