# frozen_string_literal: true

module DataIntegrity
  module Checks
    class BaseCheck
      WINDOW = 7.days

      def initialize(account)
        @account = account
      end

      def call
        {
          check_name: check_name,
          value: calculate_value,
          status: evaluate_status(calculate_value),
          warning_threshold: warning_threshold,
          critical_threshold: critical_threshold,
          details: details
        }
      end

      private

      attr_reader :account

      def evaluate_status(value)
        return :critical if critical?(value)
        return :warning if warning?(value)
        :healthy
      end

      def check_name = raise(NotImplementedError)
      def calculate_value = raise(NotImplementedError)
      def warning_threshold = raise(NotImplementedError)
      def critical_threshold = raise(NotImplementedError)
      def warning?(value) = value >= warning_threshold
      def critical?(value) = value >= critical_threshold
      def details = {}
    end
  end
end
