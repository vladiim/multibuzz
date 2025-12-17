# frozen_string_literal: true

require "test_helper"

module Attribution
  module Algorithms
    class MarkovChainTest < ActiveSupport::TestCase
      # Markov Chain attribution distributes credit based on removal effects.
      # The removal effect measures how much conversion probability drops
      # if a channel is removed from all paths.

      test "should distribute credit proportionally to removal effects" do
        credits = service.call

        assert_equal 3, credits.size

        # With removal effects: organic_search=0.3, email=0.5, paid_search=0.2
        # Total = 1.0, so credits should match removal effects directly
        assert_in_delta 0.3, find_credit(credits, "organic_search"), 0.0001
        assert_in_delta 0.5, find_credit(credits, "email"), 0.0001
        assert_in_delta 0.2, find_credit(credits, "paid_search"), 0.0001
      end

      test "should only credit channels present in journey" do
        # Journey only has organic_search and email, but removal_effects has all channels
        partial_touchpoints = touchpoints[0..1]
        credits = MarkovChain.new(partial_touchpoints, removal_effects: removal_effects).call

        assert_equal 2, credits.size

        # Only organic_search (0.3) and email (0.5) present
        # Normalized: organic = 0.3/0.8 = 0.375, email = 0.5/0.8 = 0.625
        assert_in_delta 0.375, find_credit(credits, "organic_search"), 0.0001
        assert_in_delta 0.625, find_credit(credits, "email"), 0.0001
      end

      test "should handle single touchpoint journey" do
        single_touchpoint = [touchpoints[0]]
        credits = MarkovChain.new(single_touchpoint, removal_effects: removal_effects).call

        assert_equal 1, credits.size
        assert_equal 1.0, credits[0][:credit]
        assert_equal "organic_search", credits[0][:channel]
      end

      test "should return empty array for empty journey" do
        credits = MarkovChain.new([], removal_effects: removal_effects).call

        assert_empty credits
      end

      test "should sum to exactly 1.0" do
        credits = service.call

        total = credits.sum { |c| c[:credit] }
        assert_in_delta 1.0, total, 0.0001
      end

      test "should preserve session_id and channel in output" do
        credits = service.call

        credits.each do |credit|
          assert credit[:session_id].present?, "session_id should be present"
          assert credit[:channel].present?, "channel should be present"
          assert credit[:credit].is_a?(Numeric), "credit should be numeric"
        end
      end

      test "should handle channels not in removal_effects with zero weight" do
        # Journey includes a channel not in removal_effects
        touchpoints_with_unknown = touchpoints + [{
          session_id: 103,
          channel: "unknown_channel",
          occurred_at: 30.minutes.ago
        }]

        credits = MarkovChain.new(touchpoints_with_unknown, removal_effects: removal_effects).call

        # unknown_channel gets 0 removal effect, so normalized credits only go to known channels
        assert_equal 4, credits.size

        known_total = credits.reject { |c| c[:channel] == "unknown_channel" }.sum { |c| c[:credit] }
        unknown_credit = find_credit(credits, "unknown_channel")

        assert_in_delta 1.0, known_total, 0.0001
        assert_equal 0.0, unknown_credit
      end

      test "should handle equal removal effects" do
        equal_effects = {
          "organic_search" => 0.33,
          "email" => 0.33,
          "paid_search" => 0.34
        }

        credits = MarkovChain.new(touchpoints, removal_effects: equal_effects).call

        # Should distribute roughly equally
        credits.each do |credit|
          assert_in_delta 0.33, credit[:credit], 0.02
        end
      end

      test "should handle very small removal effects" do
        small_effects = {
          "organic_search" => 0.001,
          "email" => 0.001,
          "paid_search" => 0.998
        }

        credits = MarkovChain.new(touchpoints, removal_effects: small_effects).call

        assert_in_delta 0.001, find_credit(credits, "organic_search"), 0.0001
        assert_in_delta 0.001, find_credit(credits, "email"), 0.0001
        assert_in_delta 0.998, find_credit(credits, "paid_search"), 0.0001
      end

      test "should handle duplicate channels in journey" do
        # Same channel appears twice (different sessions)
        touchpoints_with_dupe = [
          { session_id: 100, channel: "organic_search", occurred_at: 5.days.ago },
          { session_id: 101, channel: "email", occurred_at: 2.days.ago },
          { session_id: 102, channel: "organic_search", occurred_at: 1.day.ago }
        ]

        # Removal effects: organic=0.4, email=0.6
        dupe_effects = { "organic_search" => 0.4, "email" => 0.6 }

        credits = MarkovChain.new(touchpoints_with_dupe, removal_effects: dupe_effects).call

        # Should have 3 credits (one per touchpoint)
        assert_equal 3, credits.size

        # Total credit for organic_search should be 0.4, split between two touchpoints
        organic_credits = credits.select { |c| c[:channel] == "organic_search" }
        assert_equal 2, organic_credits.size
        assert_in_delta 0.2, organic_credits[0][:credit], 0.0001
        assert_in_delta 0.2, organic_credits[1][:credit], 0.0001

        # Email gets full 0.6
        assert_in_delta 0.6, find_credit(credits, "email"), 0.0001
      end

      test "should compute removal effects from paths when not provided" do
        # When no removal_effects given, compute from provided conversion_paths
        paths = [
          %w[organic_search email paid_search],
          %w[organic_search paid_search],
          %w[email paid_search],
          %w[paid_search]
        ]

        credits = MarkovChain.new(touchpoints, conversion_paths: paths).call

        assert_equal 3, credits.size
        assert_in_delta 1.0, credits.sum { |c| c[:credit] }, 0.0001

        # paid_search appears in all paths, should have high removal effect
        # organic_search and email appear in some paths
        paid_credit = find_credit(credits, "paid_search")
        assert paid_credit > 0, "paid_search should have positive credit"
      end

      test "should raise error when neither removal_effects nor conversion_paths provided" do
        assert_raises(ArgumentError) do
          MarkovChain.new(touchpoints).call
        end
      end

      private

      def service
        @service ||= MarkovChain.new(touchpoints, removal_effects: removal_effects)
      end

      def touchpoints
        @touchpoints ||= [
          { session_id: 100, channel: "organic_search", occurred_at: 5.days.ago },
          { session_id: 101, channel: "email", occurred_at: 2.days.ago },
          { session_id: 102, channel: "paid_search", occurred_at: 1.hour.ago }
        ]
      end

      def removal_effects
        # Pre-computed removal effects for channels
        # These represent how much conversion probability drops if channel removed
        @removal_effects ||= {
          "organic_search" => 0.3,
          "email" => 0.5,
          "paid_search" => 0.2
        }
      end

      def find_credit(credits, channel)
        credits.find { |c| c[:channel] == channel }&.dig(:credit) || 0.0
      end
    end
  end
end
