# frozen_string_literal: true

module AML
  module Sandbox
    class CreditLedger
      TOTAL_CREDIT = 1.0
      DEFAULT_CREDIT = 0.0
      TOLERANCE = 0.0001

      def initialize(size)
        @credits = Array.new(size, DEFAULT_CREDIT)
      end

      def [](index)
        @credits[index]
      end

      def []=(index, value)
        @credits[index] = value
      end

      def replace(new_credits)
        @credits = new_credits.dup
      end

      def normalize!
        total = sum
        return if total.zero?

        @credits = @credits.map { |c| c / total }
      end

      def validate!
        return if valid_sum?
        return normalize_edge_case! if edge_case?

        raise ::AML::CreditSumError.new(
          "Credits sum to #{sum.round(4)} but must equal #{TOTAL_CREDIT}",
          suggestion: "Add normalize! at the end, or adjust credit amounts"
        )
      end

      def sum
        @credits.sum
      end

      def length
        @credits.length
      end

      def to_a
        @credits.dup
      end

      private

      def valid_sum?
        (sum - TOTAL_CREDIT).abs < TOLERANCE
      end

      def edge_case?
        length <= 2 && sum > DEFAULT_CREDIT
      end

      def normalize_edge_case!
        normalize!
      end
    end
  end
end
