# frozen_string_literal: true

module Dashboard
  module Scopes
    class ConversionsScope
      # rubocop:disable Metrics/ParameterLists -- matches EventsScope kwarg shape
      def initialize(account:, date_range:, channels: Channels::ALL, test_mode: false, funnel: nil)
        @account = account
        @date_range = date_range
        @channels = channels
        @test_mode = test_mode
        @funnel = funnel
      end
      # rubocop:enable Metrics/ParameterLists

      def call
        base_scope
          .then { |scope| apply_date_range(scope) }
          .then { |scope| apply_channels(scope) }
          .then { |scope| apply_funnel(scope) }
      end

      private

      attr_reader :account, :date_range, :channels, :test_mode, :funnel

      def base_scope
        account
          .conversions
          .then { |scope| test_mode ? scope.test_data : scope.production }
      end

      def apply_date_range(scope)
        scope.where(converted_at: date_range.to_range)
      end

      def apply_channels(scope)
        return scope if channels == Channels::ALL

        # Join on session_id since belongs_to :session is disabled for TimescaleDB
        scope
          .joins("INNER JOIN sessions ON sessions.id = conversions.session_id")
          .where(sessions: { channel: channels })
      end

      def apply_funnel(scope)
        return scope if funnel.blank? || funnel == "all"

        scope.where(funnel: funnel)
      end
    end
  end
end
