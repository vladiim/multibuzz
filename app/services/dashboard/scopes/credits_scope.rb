module Dashboard
  module Scopes
    class CreditsScope
      def initialize(account:, models:, date_range:, channels: Channels::ALL, test_mode: false)
        @account = account
        @models = models
        @date_range = date_range
        @channels = channels
        @test_mode = test_mode
      end

      def call
        base_scope
          .then { |scope| apply_models(scope) }
          .then { |scope| apply_date_range(scope) }
          .then { |scope| apply_channels(scope) }
      end

      private

      attr_reader :account, :models, :date_range, :channels, :test_mode

      def base_scope
        account
          .attribution_credits
          .joins(:conversion)
          .then { |scope| test_mode ? scope.test_data : scope.production }
      end

      def apply_models(scope)
        scope.where(attribution_model: models)
      end

      def apply_date_range(scope)
        scope.where(conversions: { converted_at: date_range.to_range })
      end

      def apply_channels(scope)
        return scope if channels == Channels::ALL

        scope.where(channel: channels)
      end
    end
  end
end
