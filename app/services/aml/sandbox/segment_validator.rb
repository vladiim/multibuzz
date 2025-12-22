# frozen_string_literal: true

module AML
  module Sandbox
    class SegmentValidator
      TOLERANCE = 0.0001

      def initialize(segments:, outer_window:)
        @segments = segments
        @outer_window = outer_window
      end

      def call
        validate_weight_sum
        validate_no_overlaps
        validate_within_outer_window
      end

      private

      def validate_weight_sum
        return if weight_sum_valid?

        raise ::AML::ValidationError.new(
          "Segment weights sum to #{weight_sum.round(4)} but must equal 1.0",
          suggestion: "Adjust segment weights to sum to 1.0"
        )
      end

      def weight_sum
        @weight_sum ||= @segments.sum(&:weight)
      end

      def weight_sum_valid?
        (weight_sum - 1.0).abs < TOLERANCE
      end

      def validate_no_overlaps
        @segments.combination(2).each do |seg1, seg2|
          next unless seg1.overlaps?(seg2)

          raise ::AML::ValidationError.new(
            "Segments overlap: #{format_range(seg1.range)} and #{format_range(seg2.range)}",
            suggestion: "Adjust segment ranges to not overlap"
          )
        end
      end

      def validate_within_outer_window
        @segments.each do |segment|
          next if range_within_outer?(segment.range)

          raise ::AML::ValidationError.new(
            "Segment #{format_range(segment.range)} extends beyond outer window (#{format_duration(@outer_window)})",
            suggestion: "Ensure segment ranges are within the outer lookback window"
          )
        end
      end

      def range_within_outer?(range)
        range.end.to_f <= @outer_window.to_f
      end

      def format_range(range)
        "#{format_duration(range.begin)}..#{format_duration(range.end)}"
      end

      def format_duration(duration)
        days = duration.to_f / 1.day.to_f
        "#{days.round(1)} days"
      end
    end
  end
end
