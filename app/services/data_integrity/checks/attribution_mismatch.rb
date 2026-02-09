module DataIntegrity
  module Checks
    class AttributionMismatch < BaseCheck
      private

      def check_name = "attribution_mismatch"
      def warning_threshold = 25.0
      def critical_threshold = 50.0

      def calculate_value
        return 0.0 if total_conversions.zero?
        (mismatched_conversions.to_f / total_conversions * 100).round(1)
      end

      def details
        { total_conversions: total_conversions, mismatched_conversions: mismatched_conversions }
      end

      def total_conversions
        @total_conversions ||= recent_conversions.count
      end

      def mismatched_conversions
        @mismatched_conversions ||= recent_conversions
          .where(<<~SQL.squish)
            array_length(journey_session_ids, 1) > 1
            AND EXISTS (
              SELECT 1 FROM sessions AS converting_sess
              WHERE converting_sess.id = conversions.session_id
              AND EXISTS (
                SELECT 1 FROM sessions AS landing_sess
                WHERE landing_sess.id = conversions.journey_session_ids[1]
                AND landing_sess.channel IS DISTINCT FROM converting_sess.channel
              )
            )
          SQL
          .count
      end

      def recent_conversions
        account.conversions
          .where(is_test: false)
          .where("converted_at > ?", WINDOW.ago)
          .where.not(journey_session_ids: nil)
      end
    end
  end
end
