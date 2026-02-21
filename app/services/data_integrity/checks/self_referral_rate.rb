# frozen_string_literal: true

module DataIntegrity
  module Checks
    class SelfReferralRate < BaseCheck
      private

      def check_name = "self_referral_rate"
      def warning_threshold = 15.0
      def critical_threshold = 40.0

      def calculate_value
        return 0.0 if referral_sessions.zero?
        (self_referral_sessions.to_f / referral_sessions * 100).round(1)
      end

      def details
        { referral_sessions: referral_sessions, self_referral_sessions: self_referral_sessions }
      end

      def referral_sessions
        @referral_sessions ||= referral_scope.count
      end

      def self_referral_sessions
        @self_referral_sessions ||= referral_scope
          .where(<<~SQL.squish)
            EXISTS (
              SELECT 1 FROM events
              WHERE events.session_id = sessions.id
              AND LOWER(REPLACE(
                SPLIT_PART(SPLIT_PART(sessions.initial_referrer, '://', 2), '/', 1),
                'www.', ''
              )) = LOWER(REPLACE(
                SPLIT_PART(SPLIT_PART(events.properties->>'url', '://', 2), '/', 1),
                'www.', ''
              ))
            )
          SQL
          .count
      end

      def referral_scope
        account.sessions.production
          .where("started_at > ?", WINDOW.ago)
          .where.not(initial_referrer: [ nil, "" ])
      end
    end
  end
end
