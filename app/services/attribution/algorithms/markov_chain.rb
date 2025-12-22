# frozen_string_literal: true

module Attribution
  module Algorithms
    # Markov Chain attribution distributes credit based on removal effects.
    #
    # The removal effect measures how much conversion probability drops when
    # a channel is removed from all paths. Channels with higher removal effects
    # receive more credit.
    #
    class MarkovChain
      def initialize(touchpoints, removal_effects: nil, conversion_paths: nil)
        @touchpoints = touchpoints
        @provided_removal_effects = removal_effects
        @conversion_paths = conversion_paths

        validate_inputs!
      end

      def call
        return [] if touchpoints.empty?

        normalized_channel_credits
          .then { |credits| apply_credits_to_touchpoints(credits) }
      end

      private

      attr_reader :touchpoints, :conversion_paths, :provided_removal_effects

      def validate_inputs!
        return if provided_removal_effects.present? || !conversion_paths.nil?

        raise ArgumentError, "Either removal_effects or conversion_paths must be provided"
      end

      def removal_effects
        @removal_effects ||= provided_removal_effects || computed_removal_effects
      end

      def computed_removal_effects
        Markov::RemovalEffectCalculator.new(conversion_paths).normalized_effects
      end

      def normalized_channel_credits
        return equal_channel_credits if total_journey_effect.zero?

        journey_effects.transform_values { |effect| effect / total_journey_effect }
      end

      def equal_channel_credits
        journey_channels.index_with { 1.0 / journey_channels.size }
      end

      def journey_effects
        @journey_effects ||= journey_channels.index_with { |channel| removal_effects.fetch(channel, 0.0) }
      end

      def journey_channels
        @journey_channels ||= touchpoints.map { |tp| tp[:channel] }.uniq
      end

      def total_journey_effect
        @total_journey_effect ||= journey_effects.values.sum
      end

      def apply_credits_to_touchpoints(channel_credits)
        touchpoints.map { |tp| build_credit(tp, credit_for_touchpoint(tp, channel_credits)) }
      end

      def credit_for_touchpoint(touchpoint, channel_credits)
        channel = touchpoint[:channel]
        channel_credits[channel] / touchpoint_counts[channel]
      end

      def touchpoint_counts
        @touchpoint_counts ||= touchpoints.group_by { |tp| tp[:channel] }.transform_values(&:size)
      end

      def build_credit(touchpoint, credit)
        {
          session_id: touchpoint[:session_id],
          channel: touchpoint[:channel],
          credit: credit
        }
      end
    end
  end
end
