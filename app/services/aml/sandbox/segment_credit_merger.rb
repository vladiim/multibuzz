# frozen_string_literal: true

module AML
  module Sandbox
    class SegmentCreditMerger
      TOLERANCE = 0.0001

      def initialize(segments:, segment_credits:, ledger_size:)
        @segments = segments
        @segment_credits = segment_credits
        @ledger_size = ledger_size
      end

      def call
        Array.new(@ledger_size, 0.0).tap do |merged|
          normalized_segments.each_with_index do |segment, idx|
            apply_segment_credits(merged, segment, @segment_credits[idx])
          end
        end
      end

      private

      def normalized_segments
        return @segments if non_empty_weight_sum_valid?

        redistribute_weights
      end

      def non_empty_segments
        @non_empty_segments ||= @segments.reject(&:empty?)
      end

      def non_empty_weight_sum
        @non_empty_weight_sum ||= non_empty_segments.sum(&:weight)
      end

      def non_empty_weight_sum_valid?
        (non_empty_weight_sum - 1.0).abs < TOLERANCE
      end

      def redistribute_weights
        return @segments if non_empty_weight_sum.zero?

        @segments.map do |segment|
          next segment if segment.empty?

          Segment.new(
            range: segment.range,
            weight: segment.weight / non_empty_weight_sum,
            filtered_touchpoints: segment.filtered_touchpoints,
            original_indices: segment.original_indices
          )
        end
      end

      def apply_segment_credits(merged, segment, credits)
        return if segment.empty? || credits.empty?

        segment.original_indices.each_with_index do |original_idx, credit_idx|
          merged[original_idx] = credits[credit_idx] * segment.weight
        end
      end
    end
  end
end
