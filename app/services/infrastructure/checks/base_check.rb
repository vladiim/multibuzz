# frozen_string_literal: true

module Infrastructure
  module Checks
    class BaseCheck
      def call
        value = calculate_value
        {
          name: check_name,
          value: value,
          display: display_value(value),
          status: evaluate_status(value),
          warning_threshold: warning_threshold,
          critical_threshold: critical_threshold
        }
      rescue StandardError => e
        { name: check_name, value: nil, display: nil, status: :error, message: e.message }
      end

      private

      def check_name = self.class.name.demodulize.underscore
      def calculate_value = raise(NotImplementedError)
      def warning_threshold = raise(NotImplementedError)
      def critical_threshold = raise(NotImplementedError)
      def display_value(value) = value.to_s

      # Default: higher value is worse (connections, queue depth, etc.)
      # Override in checks where lower is worse (compression ratio)
      def evaluate_status(value)
        return :critical if critical?(value)
        return :warning if warning?(value)
        :ok
      end

      def warning?(value) = value >= warning_threshold
      def critical?(value) = value >= critical_threshold
    end
  end
end
