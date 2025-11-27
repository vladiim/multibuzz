# frozen_string_literal: true

require "test_helper"

module Attribution
  module Algorithms
    class ParticipationTest < ActiveSupport::TestCase
      test "should give 100% credit to each unique channel" do
        credits = service.call

        assert_equal 4, credits.size
        credits.each do |credit|
          assert_equal 1.0, credit[:credit]
        end
      end

      test "should deduplicate channels" do
        touchpoints_with_duplicates = [
          { session_id: 100, channel: "organic_search", occurred_at: 10.days.ago },
          { session_id: 101, channel: "email", occurred_at: 7.days.ago },
          { session_id: 102, channel: "organic_search", occurred_at: 5.days.ago },
          { session_id: 103, channel: "email", occurred_at: 2.days.ago },
          { session_id: 104, channel: "paid_search", occurred_at: 1.hour.ago }
        ]
        credits = Attribution::Algorithms::Participation.new(touchpoints_with_duplicates).call

        assert_equal 3, credits.size
        channels = credits.map { |c| c[:channel] }
        assert_equal ["organic_search", "email", "paid_search"], channels
      end

      test "should use first touchpoint session_id for each channel" do
        touchpoints_with_duplicates = [
          { session_id: 100, channel: "organic_search", occurred_at: 10.days.ago },
          { session_id: 101, channel: "email", occurred_at: 7.days.ago },
          { session_id: 102, channel: "organic_search", occurred_at: 5.days.ago }
        ]
        credits = Attribution::Algorithms::Participation.new(touchpoints_with_duplicates).call

        organic_credit = credits.find { |c| c[:channel] == "organic_search" }
        assert_equal 100, organic_credit[:session_id]
      end

      test "should handle single touchpoint journey" do
        credits = Attribution::Algorithms::Participation.new([touchpoints[0]]).call

        assert_equal 1, credits.size
        assert_equal 1.0, credits[0][:credit]
      end

      test "should return empty array for empty journey" do
        credits = Attribution::Algorithms::Participation.new([]).call

        assert_empty credits
      end

      test "should allow sum to exceed 1.0" do
        credits = service.call

        total = credits.sum { |c| c[:credit] }
        assert_equal 4.0, total
      end

      test "should preserve channel order by first appearance" do
        credits = service.call

        channels = credits.map { |c| c[:channel] }
        assert_equal ["organic_search", "email", "paid_social", "paid_search"], channels
      end

      test "should handle all same channel" do
        same_channel_touchpoints = [
          { session_id: 100, channel: "organic_search", occurred_at: 10.days.ago },
          { session_id: 101, channel: "organic_search", occurred_at: 5.days.ago },
          { session_id: 102, channel: "organic_search", occurred_at: 1.hour.ago }
        ]
        credits = Attribution::Algorithms::Participation.new(same_channel_touchpoints).call

        assert_equal 1, credits.size
        assert_equal 1.0, credits[0][:credit]
        assert_equal "organic_search", credits[0][:channel]
      end

      private

      def service
        @service ||= Attribution::Algorithms::Participation.new(touchpoints)
      end

      def touchpoints
        @touchpoints ||= [
          { session_id: 100, channel: "organic_search", occurred_at: 10.days.ago },
          { session_id: 101, channel: "email", occurred_at: 7.days.ago },
          { session_id: 102, channel: "paid_social", occurred_at: 5.days.ago },
          { session_id: 103, channel: "paid_search", occurred_at: 1.hour.ago }
        ]
      end
    end
  end
end
