# frozen_string_literal: true

module Attribution
  module Algorithms
    class TimeDecay
      FULL_CREDIT = 1.0
      DEFAULT_HALF_LIFE_DAYS = 7

      def initialize(touchpoints, half_life_days: DEFAULT_HALF_LIFE_DAYS)
        @touchpoints = touchpoints
        @half_life_days = half_life_days
      end

      def call
        return [] if touchpoints.empty?

        touchpoints.map { |touchpoint| build_credit(touchpoint, normalized_weight(touchpoint)) }
      end

      private

      attr_reader :touchpoints, :half_life_days

      def normalized_weight(touchpoint)
        raw_weight(touchpoint) / total_weight
      end

      def raw_weight(touchpoint)
        days_before = days_before_conversion(touchpoint)
        2**(-days_before / half_life_days.to_f)
      end

      def days_before_conversion(touchpoint)
        return 0 if touchpoints.size == 1

        (conversion_time - touchpoint_time(touchpoint)) / 1.day
      end

      def conversion_time
        @conversion_time ||= touchpoints.last[:occurred_at].to_time
      end

      def touchpoint_time(touchpoint)
        touchpoint[:occurred_at].to_time
      end

      def total_weight
        @total_weight ||= touchpoints.sum { |tp| raw_weight(tp) }
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
