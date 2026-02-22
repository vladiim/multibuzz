# frozen_string_literal: true

module Infrastructure
  module Checks
    class QueueDepth < BaseCheck
      private

      def warning_threshold = ::Infrastructure::QUEUE_DEPTH_WARNING
      def critical_threshold = ::Infrastructure::QUEUE_DEPTH_CRITICAL

      def calculate_value
        SolidQueue::Job.where(finished_at: nil).count
      end

      def display_value(value)
        value.to_s
      end
    end
  end
end
