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
        @unstable_visitors ||= ActiveRecord::Base.connection.select_value(<<~SQL.squish)
          SELECT COUNT(DISTINCT visitor_id)
          FROM (
            SELECT visitor_id
            FROM sessions
            WHERE account_id = #{account.id}
              AND is_test = false
              AND started_at > '#{WINDOW.ago.utc.iso8601}'
              AND device_fingerprint IS NOT NULL
            GROUP BY visitor_id, DATE(started_at)
            HAVING COUNT(DISTINCT device_fingerprint) > 1
          ) AS unstable
        SQL
      end

      def fingerprinted_sessions
        account.sessions.production
          .where("started_at > ?", WINDOW.ago)
          .where.not(device_fingerprint: nil)
      end
    end
  end
end
