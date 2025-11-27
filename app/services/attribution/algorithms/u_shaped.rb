# frozen_string_literal: true

module Attribution
  module Algorithms
    class UShaped
      FULL_CREDIT = 1.0
      FIRST_CREDIT = 0.4
      LAST_CREDIT = 0.4
      MIDDLE_CREDIT = 0.2

      def initialize(touchpoints)
        @touchpoints = touchpoints
      end

      def call
        return [] if touchpoints.empty?
        return single_touchpoint_credits if touchpoints.size == 1
        return two_touchpoint_credits if touchpoints.size == 2

        multi_touchpoint_credits
      end

      private

      attr_reader :touchpoints

      def single_touchpoint_credits
        [build_credit(touchpoints.first, FULL_CREDIT)]
      end

      def two_touchpoint_credits
        [
          build_credit(touchpoints.first, 0.5),
          build_credit(touchpoints.last, 0.5)
        ]
      end

      def multi_touchpoint_credits
        [
          build_credit(touchpoints.first, FIRST_CREDIT),
          *middle_touchpoint_credits,
          build_credit(touchpoints.last, LAST_CREDIT)
        ]
      end

      def middle_touchpoint_credits
        middle_touchpoints.map { |tp| build_credit(tp, credit_per_middle) }
      end

      def middle_touchpoints
        touchpoints[1..-2]
      end

      def credit_per_middle
        MIDDLE_CREDIT / middle_touchpoints.size
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
