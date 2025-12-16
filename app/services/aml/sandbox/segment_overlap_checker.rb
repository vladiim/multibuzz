# frozen_string_literal: true

module AML
  module Sandbox
    class SegmentOverlapChecker
      EPSILON = 0.001

      def self.overlaps?(range1, range2)
        new(range1, range2).call
      end

      def initialize(range1, range2)
        @range1 = range1
        @range2 = range2
      end

      def call
        r1_end > r2_start && r2_end > r1_start
      end

      private

      def r1_start
        @range1.begin.to_f
      end

      def r1_end
        @r1_end ||= @range1.end.to_f - (@range1.exclude_end? ? EPSILON : 0)
      end

      def r2_start
        @range2.begin.to_f
      end

      def r2_end
        @r2_end ||= @range2.end.to_f - (@range2.exclude_end? ? EPSILON : 0)
      end
    end
  end
end
