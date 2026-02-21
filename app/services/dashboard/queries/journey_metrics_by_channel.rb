# frozen_string_literal: true

module Dashboard
  module Queries
    class JourneyMetricsByChannel
      def initialize(scope)
        @scope = scope
      end

      def avg_channels_by_channel
        @avg_channels_by_channel ||= compute_averages(channels_per_conversion)
      end

      def avg_visits_by_channel
        @avg_visits_by_channel ||= compute_averages(visits_per_conversion)
      end

      def avg_days_by_channel
        @avg_days_by_channel ||= compute_averages(days_per_conversion)
      end

      private

      attr_reader :scope

      def compute_averages(per_conversion_counts)
        conversion_ids_by_channel.transform_values do |conversion_ids|
          values = conversion_ids.filter_map { |id| per_conversion_counts[id] }
          values.empty? ? nil : (values.sum.to_f / values.size).round(1)
        end
      end

      def conversion_ids_by_channel
        @conversion_ids_by_channel ||= scope
          .group(:channel)
          .pluck(:channel, Arel.sql("ARRAY_AGG(DISTINCT conversion_id)"))
          .to_h
      end

      def channels_per_conversion
        @channels_per_conversion ||= scope
          .group(:conversion_id)
          .distinct
          .count(:channel)
      end

      def visits_per_conversion
        @visits_per_conversion ||= calculate_journey_visits
      end

      def calculate_journey_visits
        conversion_ids = scope.distinct.pluck(:conversion_id)
        return {} if conversion_ids.empty?

        Conversion
          .where(id: conversion_ids)
          .where.not(journey_session_ids: [])
          .pluck(:id, Arel.sql("ARRAY_LENGTH(journey_session_ids, 1)"))
          .to_h
      end

      def days_per_conversion
        @days_per_conversion ||= calculate_days_per_conversion
      end

      def calculate_days_per_conversion
        conversion_ids = scope.distinct.pluck(:conversion_id)
        return {} if conversion_ids.empty?

        Conversion
          .where(id: conversion_ids)
          .where.not(journey_session_ids: [])
          .joins(
            "INNER JOIN LATERAL (
              SELECT MIN(s.started_at) as first_session_at
              FROM sessions s
              WHERE s.id = ANY(conversions.journey_session_ids)
            ) first_session ON true"
          )
          .pluck(
            :id,
            Arel.sql("EXTRACT(EPOCH FROM (conversions.converted_at - first_session.first_session_at)) / 86400.0")
          )
          .to_h
          .transform_values(&:to_f)
      end
    end
  end
end
