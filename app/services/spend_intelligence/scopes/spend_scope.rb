# frozen_string_literal: true

module SpendIntelligence
  module Scopes
    class SpendScope
      def initialize(account:, date_range:, channels: Channels::ALL, devices: nil, hours: nil, test_mode: false)
        @account = account
        @date_range = date_range
        @channels = channels
        @devices = devices
        @hours = hours
        @test_mode = test_mode
      end

      def call
        base_scope
          .then { |scope| apply_date_range(scope) }
          .then { |scope| apply_channels(scope) }
          .then { |scope| apply_devices(scope) }
          .then { |scope| apply_hours(scope) }
      end

      private

      attr_reader :account, :date_range, :channels, :devices, :hours, :test_mode

      def base_scope
        account
          .ad_spend_records
          .then { |scope| test_mode ? scope.test_data : scope.production }
      end

      def apply_date_range(scope)
        scope.for_date_range(date_range)
      end

      def apply_channels(scope)
        return scope if channels == Channels::ALL

        scope.where(channel: channels)
      end

      def apply_devices(scope)
        return scope unless devices

        scope.for_device(devices)
      end

      def apply_hours(scope)
        return scope unless hours

        scope.for_hour(hours)
      end
    end
  end
end
