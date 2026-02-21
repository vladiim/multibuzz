# frozen_string_literal: true

module Attribution
  module Algorithms
    # Shapley Value attribution distributes credit based on marginal contributions.
    #
    # Uses game theory: each channel is a "player" and credit is distributed
    # based on the average marginal contribution across all possible orderings.
    #
    # Complexity: O(2^n) where n = number of unique channels.
    # Practical limit: ~15 channels.
    #
    class ShapleyValue
      def initialize(touchpoints, conversion_paths: nil)
        @touchpoints = touchpoints
        @conversion_paths = conversion_paths

        validate_inputs!
      end

      def call
        return [] if touchpoints.empty?

        normalized_channel_credits
          .then { |credits| apply_credits_to_touchpoints(credits) }
      end

      private

      attr_reader :touchpoints, :conversion_paths

      def validate_inputs!
        return if !conversion_paths.nil?

        raise ArgumentError, "conversion_paths must be provided"
      end

      def normalized_channel_credits
        return equal_channel_credits if total_shapley_value.zero?

        shapley_values.transform_values { |value| value / total_shapley_value }
      end

      def equal_channel_credits
        journey_channels.index_with { 1.0 / journey_channels.size }
      end

      def shapley_values
        @shapley_values ||= journey_channels.index_with { |channel| shapley_value_for(channel) }
      end

      def shapley_value_for(channel)
        other_channels = all_path_channels - [ channel ]
        subsets = power_set(other_channels)

        marginal_contributions = subsets.map do |subset|
          coalition_value(subset + [ channel ]) - coalition_value(subset)
        end

        marginal_contributions.sum / subsets.size.to_f
      end

      def coalition_value(channels)
        return 0.0 if conversion_paths.empty?

        paths_completable = conversion_paths.count { |path| path_completable_with?(path, channels) }
        paths_completable.to_f / conversion_paths.size
      end

      def path_completable_with?(path, available_channels)
        path.all? { |channel| available_channels.include?(channel) }
      end

      def power_set(array)
        return [ [] ] if array.empty?

        first, *rest = array
        subsets = power_set(rest)
        subsets + subsets.map { |subset| [ first ] + subset }
      end

      def total_shapley_value
        @total_shapley_value ||= shapley_values.values.sum
      end

      def journey_channels
        @journey_channels ||= touchpoints.map { |tp| tp[:channel] }.uniq
      end

      def all_path_channels
        @all_path_channels ||= conversion_paths.flatten.uniq
      end

      def apply_credits_to_touchpoints(channel_credits)
        touchpoints.map { |tp| build_credit(tp, credit_for_touchpoint(tp, channel_credits)) }
      end

      def credit_for_touchpoint(touchpoint, channel_credits)
        channel = touchpoint[:channel]
        channel_credits.fetch(channel, 0.0) / touchpoint_counts[channel]
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
