module Dashboard
  module Scopes
    class EventsScope
      def initialize(account:, date_range:, channels: Channels::ALL, test_mode: false, funnel: nil)
        @account = account
        @date_range = date_range
        @channels = channels
        @test_mode = test_mode
        @funnel = funnel
      end

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
          .events
          .joins(:session)
          .then { |scope| test_mode ? scope.test_data : scope.production }
      end

      def apply_date_range(scope)
        scope.where(occurred_at: date_range.to_range)
      end

      def apply_channels(scope)
        return scope if channels == Channels::ALL

        scope.where(sessions: { channel: channels })
      end

      def apply_funnel(scope)
        return scope if funnel.blank? || funnel == "all"

        scope.where(funnel: funnel)
      end
    end
  end
end
