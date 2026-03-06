# frozen_string_literal: true

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
        credits = row.total_credits.to_f
        revenue = row.total_revenue.to_f
        channel = row.channel
        channel_journeys = journey_metrics_for(channel)

        {
          channel: channel,
          credits: credits,
          revenue: revenue,
          aov: credits.zero? ? 0 : (revenue / credits).round(2),
          percentage: percentage(row.total_credits),
          **channel_journeys
        }
      end

      def journey_metrics_for(channel)
        {
          avg_channels: journey_metrics.avg_channels_by_channel[channel],
          avg_visits: journey_metrics.avg_visits_by_channel[channel],
          avg_days: journey_metrics.avg_days_by_channel[channel]
        }
      end

      def percentage(credits)
        ((credits.to_f / total_credits) * 100).round(1)
      end

      def total_credits
        @total_credits ||= scope.sum(:credit).to_f
      end

      def journey_metrics
        @journey_metrics ||= JourneyMetricsByChannel.new(scope)
      end
    end
  end
end
