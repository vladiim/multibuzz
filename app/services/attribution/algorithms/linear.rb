# frozen_string_literal: true

module Attribution
  module Algorithms
    class Linear
      FULL_CREDIT = 1.0

      def initialize(touchpoints)
        @touchpoints = touchpoints
      end

      def call
        return [] if touchpoints.empty?

        touchpoints.map { |touchpoint| build_credit(touchpoint, credit_per_touchpoint) }
      end

      private

      attr_reader :touchpoints

      def credit_per_touchpoint
        @credit_per_touchpoint ||= FULL_CREDIT / touchpoints.size
      end

      def build_credit(touchpoint, credit_value)
        {
          session_id: touchpoint[:session_id],
          channel: touchpoint[:channel],
          credit: credit_value
        }
      end
    end
  end
end
