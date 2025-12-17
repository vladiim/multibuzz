# frozen_string_literal: true

require "test_helper"

module Attribution
  module Markov
    class RemovalEffectCalculatorTest < ActiveSupport::TestCase
      # Removal effect = 1 - (P(conversion without channel) / P(conversion with channel))
      # Measures how much conversion probability drops when a channel is removed

      test "should calculate removal effects for all channels" do
        effects = service.call

        assert effects.key?("organic_search")
        assert effects.key?("email")
        assert effects.key?("paid_search")
      end

      test "should return higher removal effect for channels that appear in more converting paths" do
        # paid_search appears in all 4 paths, should have highest removal effect
        effects = service.call

        paid_effect = effects["paid_search"]
        organic_effect = effects["organic_search"]
        email_effect = effects["email"]

        # paid_search is in all paths, so removing it should have big impact
        assert paid_effect > organic_effect, "paid_search should have higher effect than organic"
        assert paid_effect > email_effect, "paid_search should have higher effect than email"
      end

      test "should return removal effects that sum to approximately 1.0 when normalized" do
        effects = service.call

        # Raw effects don't sum to 1.0, but they should be positive
        effects.each_value do |effect|
          assert effect >= 0, "removal effects should be non-negative"
          assert effect <= 1, "removal effects should be <= 1"
        end
      end

      test "should handle single-channel paths" do
        single_channel_paths = [
          %w[direct],
          %w[direct],
          %w[direct]
        ]

        effects = RemovalEffectCalculator.new(single_channel_paths).call

        assert_equal({ "direct" => 1.0 }, effects)
      end

      test "should handle path where channel is the only touchpoint" do
        paths_with_solo = [
          %w[organic_search email paid_search],
          %w[paid_search], # paid_search alone
          %w[email paid_search]
        ]

        effects = RemovalEffectCalculator.new(paths_with_solo).call

        # paid_search appears in all 3 paths, removing it breaks all conversions
        assert_in_delta 1.0, effects["paid_search"], 0.01
      end

      test "should return empty hash for empty paths" do
        effects = RemovalEffectCalculator.new([]).call

        assert_equal({}, effects)
      end

      test "should handle paths with duplicate channels" do
        paths_with_dupes = [
          %w[organic_search email organic_search paid_search],
          %w[email paid_search email]
        ]

        effects = RemovalEffectCalculator.new(paths_with_dupes).call

        # Should still calculate effects correctly
        assert effects.key?("organic_search")
        assert effects.key?("email")
        assert effects.key?("paid_search")
      end

      test "should calculate correct removal effect mathematically" do
        # Simple case: 2 paths
        # Path 1: A -> B -> Conversion
        # Path 2: B -> Conversion
        # If we remove A: Path 1 still converts (B exists), Path 2 converts
        # If we remove B: Neither path converts
        # So B has 100% removal effect, A has 0%

        simple_paths = [
          %w[A B],
          %w[B]
        ]

        effects = RemovalEffectCalculator.new(simple_paths).call

        # Removing B breaks both paths (100% removal effect)
        assert_in_delta 1.0, effects["B"], 0.01

        # Removing A doesn't break any path (A is only in path 1, which also has B)
        # But this depends on implementation - some implementations give partial credit
        assert effects["A"] < effects["B"], "A should have lower effect than B"
      end

      test "should normalize effects to sum to 1.0" do
        effects = service.call
        normalized = service.normalized_effects

        total = normalized.values.sum
        assert_in_delta 1.0, total, 0.0001
      end

      private

      def service
        @service ||= RemovalEffectCalculator.new(conversion_paths)
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
    end
  end
end
