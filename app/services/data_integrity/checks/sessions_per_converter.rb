# frozen_string_literal: true

module DataIntegrity
  module Checks
    class SessionsPerConverter < BaseCheck
      private

      def check_name = "sessions_per_converter"
      def warning_threshold = 5.0
      def critical_threshold = 15.0

      def calculate_value
        return 0.0 if converting_visitor_ids.empty?
        (total_sessions_for_converters.to_f / converting_visitor_ids.size).round(1)
      end

      def details
        {
          converting_visitors: converting_visitor_ids.size,
          total_sessions: total_sessions_for_converters
        }
      end

      def converting_visitor_ids
        @converting_visitor_ids ||= account.conversions
          .where(is_test: false)
          .where("converted_at > ?", WINDOW.ago)
          .distinct
          .pluck(:visitor_id)
      end

      def total_sessions_for_converters
        @total_sessions_for_converters ||= account.sessions.production
          .where(visitor_id: converting_visitor_ids)
          .count
      end
    end
  end
end
