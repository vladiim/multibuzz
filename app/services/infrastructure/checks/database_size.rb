# frozen_string_literal: true

module Infrastructure
  module Checks
    class DatabaseSize < BaseCheck
      private

      def warning_threshold = ::Infrastructure::DATABASE_SIZE_WARNING
      def critical_threshold = ::Infrastructure::DATABASE_SIZE_CRITICAL

      def calculate_value
        result = ActiveRecord::Base.connection.execute(
          "SELECT pg_database_size(current_database())"
        )
        result.first["pg_database_size"].to_i
      end

      def display_value(value)
        ActiveSupport::NumberHelper.number_to_human_size(value)
      end
    end
  end
end
