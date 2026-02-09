module DataIntegrity
  module Checks
    class GhostSessionRate < BaseCheck
      WINDOW = 24.hours

      private

      def check_name = "ghost_session_rate"
      def warning_threshold = 20.0
      def critical_threshold = 50.0

      def calculate_value
        return 0.0 if total_sessions.zero?
        (ghost_sessions.to_f / total_sessions * 100).round(1)
      end

      def details
        { total_sessions: total_sessions, ghost_sessions: ghost_sessions }
      end

      def total_sessions
        @total_sessions ||= recent_sessions.count
      end

      def ghost_sessions
        @ghost_sessions ||= recent_sessions
          .where(initial_referrer: [nil, ""])
          .where("initial_utm IS NULL OR initial_utm = '{}'::jsonb")
          .where("click_ids IS NULL OR click_ids = '{}'::jsonb")
          .where(<<~SQL.squish)
            NOT EXISTS (SELECT 1 FROM events WHERE events.session_id = sessions.id)
          SQL
          .count
      end

      def recent_sessions
        account.sessions.production.where("started_at > ?", WINDOW.ago)
      end
    end
  end
end
