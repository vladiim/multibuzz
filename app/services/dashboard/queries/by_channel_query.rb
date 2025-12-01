module Dashboard
  module Queries
    class ByChannelQuery
      def initialize(scope)
        @scope = scope
      end

      def call
        return [] if total_credits.zero?

        aggregated_channels
          .map { |row| build_channel_row(row) }
          .sort_by { |row| -row[:credits] }
      end

      private

      attr_reader :scope

      def aggregated_channels
        scope
          .group(:channel)
          .select(:channel, "SUM(credit) as total_credits", "SUM(revenue_credit) as total_revenue")
      end

      def build_channel_row(row)
        {
          channel: row.channel,
          credits: row.total_credits.to_f,
          revenue: row.total_revenue.to_f,
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
