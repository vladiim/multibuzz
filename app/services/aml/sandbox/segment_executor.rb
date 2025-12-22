# frozen_string_literal: true

module AML
  module Sandbox
    class SegmentExecutor
      def initialize(segment:, conversion_time:, conversion_value:)
        @segment = segment
        @conversion_time = conversion_time
        @conversion_value = conversion_value
      end

      def call(&block)
        return [] if @segment.empty?

        SegmentContext
          .new(touchpoints: touchpoint_data, conversion_time: @conversion_time, conversion_value: @conversion_value)
          .execute(&block)
      end

      private

      def touchpoint_data
        @segment.filtered_touchpoints.map do |tp|
          {
            session_id: tp.session_id,
            channel: tp.channel,
            occurred_at: tp.occurred_at,
            event_type: tp.event_type,
            properties: tp.properties.to_h
          }
        end
      end
    end

    # Restricted context for executing DSL within a segment (no further nesting allowed)
    class SegmentContext < Context
      def initialize(touchpoints:, conversion_time:, conversion_value:)
        super
        @lookback_window = :segment  # Mark as already within window
      end

      def within_window(_duration_or_range, weight: nil, &_block)
        raise ::AML::ValidationError.new(
          "Cannot nest within_window more than 2 levels deep",
          suggestion: "Remove the innermost within_window block"
        )
      end
    end
  end
end
