module DataIntegrity
  module Checks
    class VisitorInflation < BaseCheck
      private

      def check_name = "visitor_inflation"
      def warning_threshold = 1.5
      def critical_threshold = 3.0

      def calculate_value
        return 0.0 if unique_fingerprints.zero?
        (unique_visitors.to_f / unique_fingerprints).round(1)
      end

      def details
        { unique_visitors: unique_visitors, unique_fingerprints: unique_fingerprints }
      end

      def unique_visitors
        @unique_visitors ||= fingerprinted_sessions.distinct.count(:visitor_id)
      end

      def unique_fingerprints
        @unique_fingerprints ||= fingerprinted_sessions.distinct.count(:device_fingerprint)
      end

      def fingerprinted_sessions
        account.sessions.production
          .where("started_at > ?", WINDOW.ago)
          .where.not(device_fingerprint: nil)
      end
    end
  end
end
