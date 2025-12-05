module Dashboard
  module Queries
    class TimeSeriesQuery
      DEFAULT_CHANNEL_LIMIT = 5

      def initialize(scope, date_range:, channel_limit: DEFAULT_CHANNEL_LIMIT)
        @scope = scope
        @date_range = date_range
        @channel_limit = channel_limit
      end

      def call
        {
          dates: dates.map(&:iso8601),
          series: top_channels.map { |channel| build_series(channel) }
        }
      end

      private

      attr_reader :scope, :date_range, :channel_limit

      def dates
        @dates ||= (date_range.start_date..date_range.end_date).to_a
      end

      def top_channels
        @top_channels ||= scope
          .group(:channel)
          .order("SUM(credit) DESC")
          .limit(channel_limit)
          .pluck(:channel)
      end

      def build_series(channel)
        {
          channel: channel,
          data: dates.map { |date| daily_data_for_channel(channel)[date.to_s] || 0 }
        }
      end

      def daily_data_for_channel(channel)
        daily_credits_by_channel[channel] || {}
      end

      def daily_credits_by_channel
        @daily_credits_by_channel ||= raw_daily_credits.each_with_object({}) do |((channel, date), credits), result|
          result[channel] ||= {}
          date_key = date.respond_to?(:strftime) ? date.strftime("%Y-%m-%d") : date.to_s
          result[channel][date_key] = credits
        end
      end

      def raw_daily_credits
        @raw_daily_credits ||= scope
          .where(channel: top_channels)
          .group(:channel, Arel.sql("DATE(conversions.converted_at)"))
          .sum(:credit)
      end
    end
  end
end
