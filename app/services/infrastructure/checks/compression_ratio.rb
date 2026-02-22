# frozen_string_literal: true

module Infrastructure
  module Checks
    class CompressionRatio < BaseCheck
      private

      def warning_threshold = ::Infrastructure::COMPRESSION_RATIO_WARNING
      def critical_threshold = ::Infrastructure::COMPRESSION_RATIO_CRITICAL

      def calculate_value
        return 100 if total_before.zero?

        ((1 - total_after.to_f / total_before) * 100).round(1)
      end

      def display_value(value)
        "#{value}%"
      end

      # Lower compression ratio is worse — inverts the default
      def warning?(value) = value <= warning_threshold
      def critical?(value) = value <= critical_threshold

      def total_before
        @total_before ||= stats.sum { |s| s[:before_bytes] }
      end

      def total_after
        @total_after ||= stats.sum { |s| s[:after_bytes] }
      end

      def stats
        @stats ||= Queries::CompressionStatsQuery.new.call
      end
    end
  end
end
