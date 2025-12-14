# frozen_string_literal: true

module AML
  module Sandbox
    class TimeDecayCalculator
      LN2 = Math.log(2)

      def initialize(touchpoints:, conversion_time:, half_life:)
        @touchpoints = touchpoints
        @conversion_time = conversion_time
        @half_life_seconds = half_life.to_f
      end

      def call
        normalize(weights)
      end

      private

      attr_reader :touchpoints, :conversion_time, :half_life_seconds

      def weights
        touchpoints.map { |tp| weight_for(tp) }
      end

      def weight_for(touchpoint)
        seconds_before = (conversion_time - touchpoint.occurred_at).to_f
        Math.exp(-LN2 * seconds_before / half_life_seconds)
      end

      def normalize(weights)
        total = weights.sum
        return weights if total.zero?

        weights.map { |w| w / total }
      end
    end
  end
end
