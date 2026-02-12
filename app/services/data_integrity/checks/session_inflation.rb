module DataIntegrity
  module Checks
    class SessionInflation < BaseCheck
      private

      def check_name = "session_inflation"
      def warning_threshold = 2.0
      def critical_threshold = 5.0

      def calculate_value
        return 0.0 if unique_fingerprints.zero?
        (total_sessions.to_f / unique_fingerprints).round(1)
      end

      def details
        { total_sessions: total_sessions, unique_fingerprints: unique_fingerprints }
      end

      def total_sessions
        @total_sessions ||= fingerprinted_sessions.count
      end

      def unique_fingerprints
        @unique_fingerprints ||= fingerprinted_sessions.distinct.count(:device_fingerprint)
      end

      def fingerprinted_sessions
        account.sessions.production.qualified
          .where("started_at > ?", WINDOW.ago)
          .where.not(device_fingerprint: nil)
      end
    end
  end
end
