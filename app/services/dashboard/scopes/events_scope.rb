module Dashboard
  module Scopes
    class EventsScope
      def initialize(account:, date_range:, channels: Channels::ALL, test_mode: false)
        @account = account
        @date_range = date_range
        @channels = channels
        @test_mode = test_mode
      end

      def call
        base_scope
          .then { |scope| apply_date_range(scope) }
          .then { |scope| apply_channels(scope) }
      end

      private

      attr_reader :account, :date_range, :channels, :test_mode

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
    end
  end
end
