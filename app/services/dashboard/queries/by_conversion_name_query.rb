# frozen_string_literal: true

module Dashboard
  module Queries
    class ByConversionNameQuery
      BUILT_IN_DIMENSIONS = {
        "conversion_type" => "conversions.conversion_type",
        "funnel" => "conversions.funnel"
      }.freeze

      DEFAULT_LIMIT = 10

      def initialize(scope, dimension: "conversion_type", limit: DEFAULT_LIMIT)
        @scope = scope
        @dimension = dimension
        @limit = limit
      end

      def call
        return [] if total_credits.zero?

        aggregated_data
          .map { |row| build_row(row) }
          .sort_by { |row| -row[:credits] }
          .first(limit)
      end

      private

      attr_reader :scope, :dimension, :limit

      def aggregated_data
        scope
          .joins(:conversion)
          .group(group_expression)
          .select(select_expression)
      end

      def group_expression
        built_in_dimension? ? BUILT_IN_DIMENSIONS[dimension] : property_expression
      end

      def select_expression
        [
          "#{group_expression} as dimension_value",
          "SUM(credit) as total_credits",
          "SUM(revenue_credit) as total_revenue",
          "COUNT(DISTINCT conversions.id) as conversion_count"
        ].join(", ")
      end

      def property_expression
        "conversions.properties->>'#{sanitized_dimension}'"
      end

      def built_in_dimension?
        BUILT_IN_DIMENSIONS.key?(dimension)
      end

      def sanitized_dimension
        @sanitized_dimension ||= dimension.to_s.gsub(/[^a-zA-Z0-9_]/, "")
      end

      def build_row(row)
        {
          channel: row.dimension_value || "(not set)",
          credits: row.total_credits.to_f,
          revenue: row.total_revenue.to_f,
          conversion_count: row.conversion_count,
          percentage: percentage(row.total_credits)
        }
      end

      def percentage(credits)
        ((credits.to_f / total_credits) * 100).round(1)
      end

      def total_credits
        @total_credits ||= scope.sum(:credit).to_f
      end
    end
  end
end
