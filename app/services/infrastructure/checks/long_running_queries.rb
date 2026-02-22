# frozen_string_literal: true

module Infrastructure
  module Checks
    class LongRunningQueries < BaseCheck
      private

      def warning_threshold = ::Infrastructure::LONG_QUERY_WARNING_COUNT
      def critical_threshold = ::Infrastructure::LONG_QUERY_CRITICAL_COUNT

      def calculate_value
        Queries::LongRunningQueriesQuery.new.call
      end

      def display_value(value)
        "#{value} queries > #{::Infrastructure::LONG_QUERY_WARNING_SECONDS}s"
      end
    end
  end
end
