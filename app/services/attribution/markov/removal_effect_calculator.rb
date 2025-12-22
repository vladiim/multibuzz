# frozen_string_literal: true

module Attribution
  module Markov
    # Calculates removal effects for each channel in conversion paths.
    #
    # Removal effect = 1 - (P(conversion without channel) / P(conversion with channel))
    # Measures how much conversion probability drops when a channel is removed.
    #
    class RemovalEffectCalculator
      FULL_EFFECT = 1.0
      ZERO_EFFECT = 0.0

      def initialize(conversion_paths)
        @conversion_paths = conversion_paths
      end

      def call
        @call ||= compute_removal_effects
      end

      def normalized_effects
        @normalized_effects ||= normalize_effects
      end

      private

      attr_reader :conversion_paths

      def compute_removal_effects
        return {} if conversion_paths.empty?

        all_channels.index_with { |channel| removal_effect_for(channel) }
      end

      def normalize_effects
        return {} if call.empty?
        return call if total_effect.zero?

        call.transform_values { |effect| effect / total_effect }
      end

      def total_effect
        @total_effect ||= call.values.sum
      end

      def removal_effect_for(channel)
        paths_without = paths_not_containing(channel)

        FULL_EFFECT - (paths_without.to_f / total_paths)
      end

      def paths_not_containing(channel)
        conversion_paths.count { |path| path.exclude?(channel) }
      end

      def all_channels
        @all_channels ||= conversion_paths.flatten.uniq
      end

      def total_paths
        @total_paths ||= conversion_paths.size
      end
    end
  end
end
