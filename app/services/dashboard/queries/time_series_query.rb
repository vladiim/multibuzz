# frozen_string_literal: true

module Dashboard
  module Queries
    class TimeSeriesQuery
      DEFAULT_CHANNEL_LIMIT = 5

      METRIC_CONFIG = {
        DashboardMetrics::CREDITS => { order: "SUM(credit) DESC" },
        DashboardMetrics::REVENUE => { order: "SUM(revenue_credit) DESC" },
        DashboardMetrics::CONVERSIONS => { order: "COUNT(DISTINCT conversion_id) DESC" },
        DashboardMetrics::AOV => { order: "SUM(revenue_credit) DESC" },
        DashboardMetrics::AVG_VISITS => { order: "SUM(credit) DESC" },
        DashboardMetrics::AVG_CHANNELS => { order: "SUM(credit) DESC" },
        DashboardMetrics::AVG_DAYS => { order: "SUM(credit) DESC" }
      }.freeze

      def initialize(scope, date_range:, channel_limit: DEFAULT_CHANNEL_LIMIT, metric: nil)
        @scope = scope
        @date_range = date_range
        @channel_limit = channel_limit
        @metric = metric.presence || DashboardMetrics::CREDITS
      end

      def call
        {
          dates: dates.map(&:iso8601),
          series: top_channels.map { |channel| build_series(channel) }
        }
      end

      private

      attr_reader :scope, :date_range, :channel_limit, :metric

      def dates
        @dates ||= (date_range.start_date..date_range.end_date).to_a
      end

      def top_channels
        @top_channels ||= scope
          .group(:channel)
          .order(Arel.sql(metric_config[:order]))
          .limit(channel_limit)
          .pluck(:channel)
      end

      def metric_config
        METRIC_CONFIG.fetch(metric, METRIC_CONFIG[DashboardMetrics::CREDITS])
      end

      AVERAGE_METRICS = [
        DashboardMetrics::AOV, DashboardMetrics::AVG_VISITS,
        DashboardMetrics::AVG_CHANNELS, DashboardMetrics::AVG_DAYS
      ].freeze

      def build_series(channel)
        {
          channel: channel,
          data: dates.map { |date| series_value(channel, date) }
        }
      end

      def series_value(channel, date)
        value = daily_data_for_channel(channel)[date.to_s]
        return value&.to_f if AVERAGE_METRICS.include?(metric)

        (value || 0).to_f
      end

      def daily_data_for_channel(channel)
        daily_data_by_channel[channel] || {}
      end

      def daily_data_by_channel
        @daily_data_by_channel ||= raw_daily_data.each_with_object({}) do |((channel, date), value), result|
          result[channel] ||= {}
          date_key = date.respond_to?(:strftime) ? date.strftime("%Y-%m-%d") : date.to_s
          result[channel][date_key] = value
        end
      end

      def raw_daily_data
        @raw_daily_data ||= aggregate_daily_data
      end

      AGGREGATORS = {
        DashboardMetrics::CONVERSIONS => :aggregate_conversions,
        DashboardMetrics::REVENUE => :aggregate_revenue,
        DashboardMetrics::AOV => :aggregate_aov,
        DashboardMetrics::AVG_VISITS => :aggregate_avg_visits,
        DashboardMetrics::AVG_CHANNELS => :aggregate_avg_channels,
        DashboardMetrics::AVG_DAYS => :aggregate_avg_days
      }.freeze

      def aggregate_daily_data
        send(AGGREGATORS.fetch(metric, :aggregate_credits))
      end

      def aggregate_credits = base_grouped_query.sum(:credit)
      def aggregate_revenue = base_grouped_query.sum(:revenue_credit)
      def aggregate_conversions = base_grouped_query.count("DISTINCT conversion_id")

      def base_grouped_query
        scope
          .where(channel: top_channels)
          .group(:channel, Arel.sql("DATE(conversions.converted_at)"))
      end

      # --- AOV ---

      def aggregate_aov
        revenue = base_grouped_query.sum(:revenue_credit)
        credits = base_grouped_query.sum(:credit)

        revenue.each_with_object({}) do |((channel, date), rev), result|
          cred = credits[[ channel, date ]] || 0
          result[[ channel, date ]] = cred.zero? ? 0 : (rev.to_f / cred.to_f).round(2)
        end
      end

      # --- Journey Metrics ---

      def aggregate_avg_visits = aggregate_journey_metric(:journey_visits_per_conversion)
      def aggregate_avg_channels = aggregate_journey_metric(:journey_channels_per_conversion)
      def aggregate_avg_days = aggregate_journey_metric(:journey_days_per_conversion)

      def aggregate_journey_metric(method)
        tuples = distinct_conversion_tuples(exclude_empty_journeys: true)
        return {} if tuples.empty?

        average_metric_by_group(tuples, send(method, tuples))
      end

      def distinct_conversion_tuples(exclude_empty_journeys: false)
        base = scope.where(channel: top_channels)
        base = base.where.not("conversions.journey_session_ids = '{}'") if exclude_empty_journeys

        base.distinct.pluck(:channel, :conversion_id, Arel.sql("DATE(conversions.converted_at)"))
      end

      def journey_visits_per_conversion(tuples)
        Conversion
          .where(id: tuples.map { |_, cid, _| cid }.uniq)
          .where.not(journey_session_ids: [])
          .pluck(:id, Arel.sql("ARRAY_LENGTH(journey_session_ids, 1)"))
          .to_h
      end

      def journey_channels_per_conversion(tuples)
        Conversion
          .where(id: tuples.map { |_, cid, _| cid }.uniq)
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

      def journey_days_per_conversion(tuples)
        Conversion
          .where(id: tuples.map { |_, cid, _| cid }.uniq)
          .where.not(journey_session_ids: [])
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

      def average_metric_by_group(tuples, per_conversion_values)
        tuples
          .group_by { |ch, _, dt| [ ch, dt.respond_to?(:strftime) ? dt.strftime("%Y-%m-%d") : dt.to_s ] }
          .transform_values do |records|
            values = records.filter_map { |_, cid, _| per_conversion_values[cid] }
            values.empty? ? 0 : (values.sum.to_f / values.size).round(1)
          end
      end
    end
  end
end
