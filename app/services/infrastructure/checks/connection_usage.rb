# frozen_string_literal: true

module Infrastructure
  module Checks
    class ConnectionUsage < BaseCheck
      private

      def warning_threshold = ::Infrastructure::CONNECTION_USAGE_WARNING
      def critical_threshold = ::Infrastructure::CONNECTION_USAGE_CRITICAL

      def calculate_value
        return 0 if max_connections.zero?

        (active_connections.to_f / max_connections * 100).round(1)
      end

      def display_value(value)
        "#{value}% (#{active_connections}/#{max_connections})"
      end

      def active_connections
        @active_connections ||= ActiveRecord::Base.connection.execute(
          "SELECT count(*) FROM pg_stat_activity WHERE state IS NOT NULL"
        ).first["count"].to_i
      end

      def max_connections
        @max_connections ||= ActiveRecord::Base.connection.execute(
          "SHOW max_connections"
        ).first["max_connections"].to_i
      end
    end
  end
end
