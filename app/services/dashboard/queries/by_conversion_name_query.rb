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
          "COUNT(DISTINCT conversions.id) as conversion_count",
          "ARRAY_AGG(DISTINCT attribution_credits.conversion_id) as conversion_ids"
        ].join(", ")
      end

      # Properties are stored FLAT at root level: { "location" => "Sydney" }
      # NOT nested: { "properties" => { "location" => "Sydney" } }
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
        dimension_value = row.dimension_value || "(not set)"
        conversion_ids = row.conversion_ids || []

        {
          channel: dimension_value,
          credits: row.total_credits.to_f,
          revenue: row.total_revenue.to_f,
          conversion_count: row.conversion_count,
          percentage: percentage(row.total_credits),
          avg_channels: calculate_avg_channels(conversion_ids),
          avg_visits: calculate_avg_visits(conversion_ids),
          avg_days: calculate_avg_days(conversion_ids),
          by_channel: channel_breakdown_for(dimension_value)
        }
      end

      def percentage(credits)
        ((credits.to_f / total_credits) * 100).round(1)
      end

      def channel_breakdown_for(dimension_value)
        channel_breakdown[dimension_value] || []
      end

      def channel_breakdown
        @channel_breakdown ||= build_channel_breakdown
      end

      def build_channel_breakdown
        scope
          .joins(:conversion)
          .group(group_expression, :channel)
          .select(
            "#{group_expression} as dimension_value",
            :channel,
            "SUM(credit) as total_credits"
          )
          .each_with_object({}) do |row, result|
            dim_value = row.dimension_value || "(not set)"
            result[dim_value] ||= []
            result[dim_value] << { channel: row.channel, credits: row.total_credits.to_f }
          end
          .transform_values { |channels| channels.sort_by { |c| -c[:credits] } }
      end

      def total_credits
        @total_credits ||= scope.sum(:credit).to_f
      end

      def calculate_avg(conversion_ids, lookup)
        values = conversion_ids.filter_map { |id| lookup[id] }
        return nil if values.empty?

        (values.sum.to_f / values.size).round(1)
      end

      def calculate_avg_channels(ids) = calculate_avg(ids, channels_per_conversion)
      def calculate_avg_visits(ids) = calculate_avg(ids, visits_per_conversion)
      def calculate_avg_days(ids) = calculate_avg(ids, days_per_conversion)

      def journey_conversions
        @journey_conversions ||= Conversion
          .where(id: scope.distinct.pluck(:conversion_id))
          .where.not(journey_session_ids: [])
      end

      def channels_per_conversion
        @channels_per_conversion ||= journey_conversions
          .joins(
            "INNER JOIN LATERAL (
              SELECT COUNT(DISTINCT s.channel) as channel_count
              FROM sessions s
              WHERE s.id = ANY(conversions.journey_session_ids)
            ) journey_channels ON true"
          )
          .pluck(:id, Arel.sql("journey_channels.channel_count"))
          .to_h
      end

      def visits_per_conversion
        @visits_per_conversion ||= journey_conversions
          .pluck(:id, Arel.sql("ARRAY_LENGTH(journey_session_ids, 1)"))
          .to_h
      end

      def days_per_conversion
        @days_per_conversion ||= journey_conversions
          .joins(
            "INNER JOIN LATERAL (
              SELECT MIN(s.started_at) as first_session_at
              FROM sessions s
              WHERE s.id = ANY(conversions.journey_session_ids)
            ) first_session ON true"
          )
          .pluck(:id, Arel.sql("EXTRACT(EPOCH FROM (conversions.converted_at - first_session.first_session_at)) / 86400.0"))
          .to_h
          .transform_values(&:to_f)
      end
    end
  end
end
