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
        daily_data = daily_credits_for(channel)

        {
          channel: channel,
          data: dates.map { |date| daily_data[date.to_s] || 0 }
        }
      end

      def daily_credits_for(channel)
        scope
          .where(channel: channel)
          .group("DATE(conversions.converted_at)")
          .sum(:credit)
          .transform_keys(&:to_s)
      end
    end
  end
end
