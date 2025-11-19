# frozen_string_literal: true

module Attribution
  module Algorithms
    class FirstTouch
      FULL_CREDIT = 1.0

      def initialize(touchpoints)
        @touchpoints = touchpoints
      end

      def call
        return [] if touchpoints.empty?

        [build_credit(touchpoints.first, FULL_CREDIT)]
      end

      private

      attr_reader :touchpoints

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
