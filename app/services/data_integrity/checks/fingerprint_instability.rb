module DataIntegrity
  module Checks
    class FingerprintInstability < BaseCheck
      private

      def check_name = "fingerprint_instability"
      def warning_threshold = 10.0
      def critical_threshold = 25.0

      def calculate_value
        return 0.0 if total_visitors_with_sessions.zero?
        (unstable_visitors.to_f / total_visitors_with_sessions * 100).round(1)
      end

      def details
        {
          total_visitors: total_visitors_with_sessions,
          unstable_visitors: unstable_visitors
        }
      end

      def total_visitors_with_sessions
        @total_visitors_with_sessions ||= fingerprinted_sessions.distinct.count(:visitor_id)
      end

      def unstable_visitors
        @unstable_visitors ||= account.sessions.production
          .where("started_at > ?", WINDOW.ago)
          .where.not(device_fingerprint: nil)
          .group(:visitor_id, Arel.sql("DATE(started_at)"))
          .having("COUNT(DISTINCT device_fingerprint) > 1")
          .select(:visitor_id)
          .distinct
          .count(:visitor_id)
          .size
      end

      def fingerprinted_sessions
        account.sessions.production
          .where("started_at > ?", WINDOW.ago)
          .where.not(device_fingerprint: nil)
      end
    end
  end
end
