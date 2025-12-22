# frozen_string_literal: true

module AML
  module Sandbox
    class SegmentBuilder
      SECONDS_PER_DAY = 86_400.0

      def initialize(range_or_duration:, weight:, parent_touchpoints:, conversion_time:)
        @range_or_duration = range_or_duration
        @weight = weight
        @parent_touchpoints = parent_touchpoints
        @conversion_time = conversion_time
      end

      def call
        Segment.new(
          range: normalized_range,
          weight: @weight,
          filtered_touchpoints: filtered_touchpoints,
          original_indices: original_indices
        )
      end

      private

      attr_reader :parent_touchpoints, :conversion_time

      def normalized_range
        @normalized_range ||= RangeNormalizer.normalize(@range_or_duration)
      end

      def filtered_touchpoints
        @filtered_touchpoints ||= TouchpointCollection.new(filtered_touchpoint_data)
      end

      def filtered_touchpoint_data
        indexed_filtered_touchpoints.map(&:last)
      end

      def original_indices
        @original_indices ||= indexed_filtered_touchpoints.map(&:first)
      end

      def indexed_filtered_touchpoints
        @indexed_filtered_touchpoints ||= parent_touchpoints
          .each_with_index
          .select { |tp, _idx| seconds_range.cover?(days_before_conversion(tp)) }
          .map { |tp, idx| [idx, touchpoint_to_hash(tp)] }
      end

      def seconds_range
        @seconds_range ||= Range.new(
          normalized_range.begin.to_f,
          normalized_range.end.to_f,
          normalized_range.exclude_end?
        )
      end

      def days_before_conversion(touchpoint)
        (conversion_time - touchpoint.occurred_at).to_f / SECONDS_PER_DAY * SECONDS_PER_DAY
      end

      def touchpoint_to_hash(safe_touchpoint)
        {
          session_id: safe_touchpoint.session_id,
          channel: safe_touchpoint.channel,
          occurred_at: safe_touchpoint.occurred_at,
          event_type: safe_touchpoint.event_type,
          properties: safe_touchpoint.properties.to_h
        }
      end
    end
  end
end
