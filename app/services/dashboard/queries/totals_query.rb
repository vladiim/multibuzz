# frozen_string_literal: true

module Dashboard
  module Queries
    class TotalsQuery
      DECIMAL_PRECISION = 1
      CURRENCY_PRECISION = 2
      MEDIAN_DIVISOR = 2

      def initialize(scope, prior_scope: nil, sessions_scope: nil, prior_sessions_scope: nil)
        @scope = scope
        @prior_scope = prior_scope
        @sessions_scope = sessions_scope
        @prior_sessions_scope = prior_sessions_scope
      end

      def call
        {
          conversions: sum_credits,
          revenue: sum_revenue,
          aov: calculate_aov,
          avg_days_to_convert: avg_days_to_convert,
          avg_channels_to_convert: avg_channels_to_convert,
          avg_visits_to_convert: avg_visits_to_convert,
          prior_period: prior_period_data
        }
      end

      private

      attr_reader :scope, :prior_scope, :sessions_scope, :prior_sessions_scope

      def sum_credits
        @sum_credits ||= scope.sum(:credit).to_f
      end

      def sum_revenue
        @sum_revenue ||= scope.sum(:revenue_credit).to_f
      end

      def calculate_aov
        return nil if sum_credits.zero?

        (sum_revenue / sum_credits).round(CURRENCY_PRECISION)
      end

      def avg_days_to_convert
        return nil if conversion_count.zero?

        days = days_per_conversion
        return nil if days.empty?

        (days.sum / days.size).round(DECIMAL_PRECISION)
      end

      def days_per_conversion
        @days_per_conversion ||= calculate_days_per_conversion
      end

      def calculate_days_per_conversion
        conversion_ids = scope.distinct.pluck(:conversion_id)
        return [] if conversion_ids.empty?

        # Query conversions with their journey timing
        # Skips conversions without journey data (empty session IDs)
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
          .pluck(Arel.sql(
            "EXTRACT(EPOCH FROM (conversions.converted_at - first_session.first_session_at)) / 86400.0"
          ))
          .compact
          .map(&:to_f)
      end

      def avg_channels_to_convert
        return nil if conversion_count.zero?
        return nil if channels_per_conversion.empty?

        median(channels_per_conversion.values).round(DECIMAL_PRECISION)
      end

      def avg_visits_to_convert
        return nil if conversion_count.zero?

        visits = journey_visits_per_conversion
        return nil if visits.empty?

        median(visits.values).round(DECIMAL_PRECISION)
      end

      def channels_per_conversion
        @channels_per_conversion ||= calculate_journey_channels
      end

      def calculate_journey_channels
        conversion_ids = scope.distinct.pluck(:conversion_id)
        return {} if conversion_ids.empty?

        Conversion
          .where(id: conversion_ids)
          .where.not(journey_session_ids: [])
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
        @visits_per_conversion ||= scope
          .group(:conversion_id)
          .count
      end

      def journey_visits_per_conversion
        @journey_visits_per_conversion ||= calculate_journey_visits
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

      def conversion_count
        @conversion_count ||= scope.distinct.count(:conversion_id)
      end

      def prior_period_data
        return empty_prior_period unless prior_scope

        prior_conversions = prior_scope.sum(:credit).to_f
        prior_revenue = prior_scope.sum(:revenue_credit).to_f

        {
          conversions: prior_conversions,
          revenue: prior_revenue,
          aov: prior_conversions.positive? ? (prior_revenue / prior_conversions).round(CURRENCY_PRECISION) : nil
        }
      end

      def empty_prior_period
        { conversions: 0, revenue: 0, aov: nil }
      end

      def median(values)
        return nil if values.empty?

        sorted = values.map(&:to_f).sort
        midpoint = sorted.size / MEDIAN_DIVISOR

        sorted.size.odd? ? sorted[midpoint] : (sorted[midpoint - 1] + sorted[midpoint]) / MEDIAN_DIVISOR.to_f
      end
    end
  end
end
