module DataIntegrity
  module Checks
    class MissingFingerprintRate < BaseCheck
      WINDOW = 24.hours

      private

      def check_name = "missing_fingerprint_rate"
      def warning_threshold = 5.0
      def critical_threshold = 20.0

      def calculate_value
        return 0.0 if total_sessions.zero?
        (missing_fingerprint_sessions.to_f / total_sessions * 100).round(1)
      end

      def details
        { total_sessions: total_sessions, missing_fingerprint_sessions: missing_fingerprint_sessions }
      end

      def total_sessions
        @total_sessions ||= recent_sessions.count
      end

      def missing_fingerprint_sessions
        @missing_fingerprint_sessions ||= recent_sessions.where(device_fingerprint: nil).count
      end

      def recent_sessions
        account.sessions.production.where("started_at > ?", WINDOW.ago)
      end
    end
  end
end
