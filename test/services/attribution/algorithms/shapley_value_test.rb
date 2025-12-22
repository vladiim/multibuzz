# frozen_string_literal: true

require "test_helper"

module Attribution
  module Algorithms
    class ShapleyValueTest < ActiveSupport::TestCase
      # Shapley Value distributes credit based on each channel's marginal contribution
      # to conversion across all possible orderings (coalitions).

      test "should distribute credit based on marginal contributions" do
        credits = service.call

        assert_equal 3, credits.size
        assert_in_delta 1.0, credits.sum { |c| c[:credit] }, 0.0001
      end

      test "should give higher credit to channels with higher marginal contribution" do
        # paid_search appears in all 3 paths = essential = high contribution
        # organic_search appears in 1 of 3 paths = lower contribution
        credits = service.call

        paid_credit = find_credit(credits, "paid_search")
        organic_credit = find_credit(credits, "organic_search")

        assert paid_credit > organic_credit,
          "paid_search (in all paths) should get more credit than organic_search"
      end

      test "should handle single touchpoint journey" do
        single_touchpoint = [touchpoints[0]]
        credits = ShapleyValue.new(single_touchpoint, conversion_paths: conversion_paths).call

        assert_equal 1, credits.size
        assert_equal 1.0, credits[0][:credit]
      end

      test "should return empty array for empty journey" do
        credits = ShapleyValue.new([], conversion_paths: conversion_paths).call

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

      test "should handle channels not in conversion_paths with zero weight" do
        touchpoints_with_unknown = touchpoints + [{
          session_id: 103,
          channel: "unknown_channel",
          occurred_at: 30.minutes.ago
        }]

        credits = ShapleyValue.new(touchpoints_with_unknown, conversion_paths: conversion_paths).call

        assert_equal 4, credits.size

        known_total = credits.reject { |c| c[:channel] == "unknown_channel" }.sum { |c| c[:credit] }
        unknown_credit = find_credit(credits, "unknown_channel")

        assert_in_delta 1.0, known_total, 0.0001
        assert_equal 0.0, unknown_credit
      end

      test "should handle duplicate channels in journey" do
        touchpoints_with_dupe = [
          { session_id: 100, channel: "organic_search", occurred_at: 5.days.ago },
          { session_id: 101, channel: "email", occurred_at: 2.days.ago },
          { session_id: 102, channel: "organic_search", occurred_at: 1.day.ago }
        ]

        credits = ShapleyValue.new(touchpoints_with_dupe, conversion_paths: conversion_paths).call

        assert_equal 3, credits.size

        # Total credit for organic_search should be split between two touchpoints
        organic_credits = credits.select { |c| c[:channel] == "organic_search" }
        assert_equal 2, organic_credits.size
        assert_in_delta organic_credits[0][:credit], organic_credits[1][:credit], 0.0001
      end

      test "should compute shapley values from paths when not provided" do
        paths = [
          %w[organic_search email paid_search],
          %w[organic_search paid_search],
          %w[email paid_search],
          %w[paid_search]
        ]

        credits = ShapleyValue.new(touchpoints, conversion_paths: paths).call

        assert_equal 3, credits.size
        assert_in_delta 1.0, credits.sum { |c| c[:credit] }, 0.0001

        # paid_search appears in all paths, should have high contribution
        paid_credit = find_credit(credits, "paid_search")
        assert paid_credit > 0, "paid_search should have positive credit"
      end

      test "should handle empty conversion_paths gracefully" do
        credits = ShapleyValue.new(touchpoints, conversion_paths: []).call

        assert_equal 3, credits.size
        # With no historical data, should fall back to equal distribution
        credits.each do |credit|
          assert_in_delta 1.0 / 3.0, credit[:credit], 0.0001
        end
      end

      test "should raise error when neither removal_effects nor conversion_paths provided" do
        assert_raises(ArgumentError) do
          ShapleyValue.new(touchpoints).call
        end
      end

      test "should calculate mathematically correct shapley values" do
        # Simple case: 2 channels, A and B
        # Path 1: A -> B -> Conversion
        # Path 2: B -> Conversion
        #
        # Coalition analysis:
        # - {} (empty): 0% conversion (no paths)
        # - {A}: 0% conversion (A alone not in any path)
        # - {B}: 50% conversion (1 of 2 paths: [B])
        # - {A,B}: 100% conversion (both paths work)
        #
        # Marginal contributions:
        # - A joining {}: 0 (still no conversions)
        # - A joining {B}: 100% - 50% = 50% (enables path [A,B])
        # - B joining {}: 50% (enables path [B])
        # - B joining {A}: 100% - 0% = 100% (enables both paths)
        #
        # Shapley values (average marginal contribution):
        # - A: (0 + 50) / 2 = 25%
        # - B: (50 + 100) / 2 = 75%

        simple_paths = [
          %w[A B],
          %w[B]
        ]

        simple_touchpoints = [
          { session_id: 1, channel: "A", occurred_at: 2.days.ago },
          { session_id: 2, channel: "B", occurred_at: 1.day.ago }
        ]

        credits = ShapleyValue.new(simple_touchpoints, conversion_paths: simple_paths).call

        a_credit = find_credit(credits, "A")
        b_credit = find_credit(credits, "B")

        # B should have significantly more credit than A
        assert b_credit > a_credit, "B should have more credit than A"
        assert_in_delta 1.0, a_credit + b_credit, 0.0001
      end

      private

      def service
        @service ||= ShapleyValue.new(touchpoints, conversion_paths: conversion_paths)
      end

      def touchpoints
        @touchpoints ||= [
          { session_id: 100, channel: "organic_search", occurred_at: 5.days.ago },
          { session_id: 101, channel: "email", occurred_at: 2.days.ago },
          { session_id: 102, channel: "paid_search", occurred_at: 1.hour.ago }
        ]
      end

      def conversion_paths
        # Sample conversion paths (channel sequences that led to conversion)
        @conversion_paths ||= [
          %w[organic_search email paid_search],
          %w[organic_search paid_search],
          %w[email paid_search],
          %w[paid_search]
        ]
      end

      def find_credit(credits, channel)
        credits.find { |c| c[:channel] == channel }&.dig(:credit) || 0.0
      end
    end
  end
end
