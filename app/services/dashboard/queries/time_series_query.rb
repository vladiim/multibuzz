module Dashboard
  module Queries
    class TimeSeriesQuery
      DEFAULT_CHANNEL_LIMIT = 5

      module Metrics
        CREDITS = "credits"
        REVENUE = "revenue"
        CONVERSIONS = "conversions"
      end

      METRIC_CONFIG = {
        Metrics::CREDITS => { order: "SUM(credit) DESC" },
        Metrics::REVENUE => { order: "SUM(revenue_credit) DESC" },
        Metrics::CONVERSIONS => { order: "COUNT(DISTINCT conversion_id) DESC" }
      }.freeze

      def initialize(scope, date_range:, channel_limit: DEFAULT_CHANNEL_LIMIT, metric: nil)
        @scope = scope
        @date_range = date_range
        @channel_limit = channel_limit
        @metric = metric.presence || Metrics::CREDITS
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
        METRIC_CONFIG.fetch(metric, METRIC_CONFIG[Metrics::CREDITS])
      end

      def build_series(channel)
        {
          channel: channel,
          data: dates.map { |date| (daily_data_for_channel(channel)[date.to_s] || 0).to_f }
        }
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

      def aggregate_daily_data
        base_query = scope
          .where(channel: top_channels)
          .group(:channel, Arel.sql("DATE(conversions.converted_at)"))

        case metric
        when Metrics::CONVERSIONS
          base_query.count("DISTINCT conversion_id")
        when Metrics::REVENUE
          base_query.sum(:revenue_credit)
        else
          base_query.sum(:credit)
        end
      end
    end
  end
end
