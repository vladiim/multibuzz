# frozen_string_literal: true

module DataIntegrity
  module Checks
    class EventVolume < BaseCheck
      PERIOD = 24.hours
      WARNING_DROP = -30.0
      CRITICAL_DROP = -60.0
      WARNING_SPIKE = 200.0
      CRITICAL_SPIKE = 500.0

      private

      def check_name = "event_volume"
      def warning_threshold = WARNING_DROP
      def critical_threshold = CRITICAL_DROP

      def calculate_value
        return 0.0 if previous_count.zero? && current_count.zero?
        return CRITICAL_SPIKE + 1 if previous_count.zero?
        ((current_count - previous_count).to_f / previous_count * 100).round(1)
      end

      def warning?(value)
        value <= WARNING_DROP || value >= WARNING_SPIKE
      end

      def critical?(value)
        value <= CRITICAL_DROP || value >= CRITICAL_SPIKE
      end

      def details
        {
          current_count: current_count,
          previous_count: previous_count,
          change_percent: calculate_value
        }
      end

      def current_count
        @current_count ||= account.events
          .where(is_test: false)
          .where("occurred_at > ?", PERIOD.ago)
          .count
      end

      def previous_count
        @previous_count ||= account.events
          .where(is_test: false)
          .where("occurred_at > ? AND occurred_at <= ?", (PERIOD * 2).ago, PERIOD.ago)
          .count
      end
    end
  end
end
