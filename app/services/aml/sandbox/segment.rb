# frozen_string_literal: true

module AML
  module Sandbox
    class Segment
      attr_reader :range, :weight, :filtered_touchpoints, :original_indices

      alias_method :touchpoints, :filtered_touchpoints

      def initialize(range:, weight:, filtered_touchpoints:, original_indices:)
        @range = range
        @weight = weight
        @filtered_touchpoints = filtered_touchpoints
        @original_indices = original_indices
      end

      def empty?
        filtered_touchpoints.empty?
      end

      def overlaps?(other)
        SegmentOverlapChecker.overlaps?(range, other.range)
      end
    end
  end
end
