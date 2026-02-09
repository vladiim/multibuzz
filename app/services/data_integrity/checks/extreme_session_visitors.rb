module DataIntegrity
  module Checks
    class ExtremeSessionVisitors < BaseCheck
      WINDOW = 30.days
      SESSION_THRESHOLD = 50

      private

      def check_name = "extreme_session_visitors"
      def warning_threshold = 1.0
      def critical_threshold = 5.0

      def calculate_value
        return 0.0 if total_visitors.zero?
        (extreme_visitors.to_f / total_visitors * 100).round(1)
      end

      def details
        { total_visitors: total_visitors, extreme_visitors: extreme_visitors }
      end

      def total_visitors
        @total_visitors ||= recent_sessions.distinct.count(:visitor_id)
      end

      def extreme_visitors
        @extreme_visitors ||= recent_sessions
          .group(:visitor_id)
          .having("COUNT(*) > ?", SESSION_THRESHOLD)
          .count
          .size
      end

      def recent_sessions
        account.sessions.production.where("started_at > ?", WINDOW.ago)
      end
    end
  end
end
