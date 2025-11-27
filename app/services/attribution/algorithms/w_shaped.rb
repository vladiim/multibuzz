# frozen_string_literal: true

module Attribution
  module Algorithms
    class WShaped
      FULL_CREDIT = 1.0
      KEY_POSITION_CREDIT = 0.3
      OTHER_CREDIT = 0.1

      def initialize(touchpoints)
        @touchpoints = touchpoints
      end

      def call
        return [] if touchpoints.empty?
        return single_touchpoint_credits if touchpoints.size == 1
        return two_touchpoint_credits if touchpoints.size == 2
        return three_touchpoint_credits if touchpoints.size == 3

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

      def three_touchpoint_credits
        credit_each = FULL_CREDIT / 3.0
        touchpoints.map { |tp| build_credit(tp, credit_each) }
      end

      def multi_touchpoint_credits
        touchpoints.each_with_index.map do |tp, index|
          credit = credit_for_position(index)
          build_credit(tp, credit)
        end
      end

      def credit_for_position(index)
        return KEY_POSITION_CREDIT if key_position?(index)

        credit_per_other
      end

      def key_position?(index)
        index == first_index || index == middle_index || index == last_index
      end

      def first_index
        0
      end

      def middle_index
        touchpoints.size / 2
      end

      def last_index
        touchpoints.size - 1
      end

      def credit_per_other
        OTHER_CREDIT / other_count
      end

      def other_count
        touchpoints.size - 3
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
