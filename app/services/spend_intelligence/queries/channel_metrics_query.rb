# frozen_string_literal: true

module SpendIntelligence
  module Queries
    class ChannelMetricsQuery
      MICRO_UNIT = AdSpendRecord::MICRO_UNIT

      def initialize(spend_scope:, credits_scope:)
        @spend_scope = spend_scope
        @credits_scope = credits_scope
      end

      def call
        channels.map { |channel| build_channel_metrics(channel) }
          .sort_by { |row| -(row[:spend_micros] || 0) }
      end

      def blended_roas
        return nil unless total_spend_micros.positive?

        (total_revenue / spend_in_units(total_spend_micros)).round(2)
      end

      def total_spend_micros
        @total_spend_micros ||= channel_spend.values.sum
      end

      def total_revenue
        @total_revenue ||= channel_revenue.values.sum.to_f
      end

      private

      attr_reader :spend_scope, :credits_scope

      def channels
        (channel_spend.keys + channel_revenue.keys).uniq
      end

      def build_channel_metrics(channel)
        spend = channel_spend[channel] || 0
        revenue = (channel_revenue[channel] || 0).to_f
        platform_value = (channel_platform_value[channel] || 0).to_f

        {
          channel: channel,
          spend_micros: spend,
          attributed_revenue: revenue,
          roas: roas(spend, revenue),
          platform_roas: roas(spend, platform_value),
          impressions: channel_impressions[channel] || 0,
          clicks: channel_clicks[channel] || 0
        }
      end

      def roas(spend_micros, revenue)
        return nil unless spend_micros.positive?

        (revenue / spend_in_units(spend_micros)).round(2)
      end

      def spend_in_units(micros)
        micros.to_d / MICRO_UNIT
      end

      # --- Aggregations ---

      def channel_spend
        @channel_spend ||= spend_scope.group(:channel).sum(:spend_micros)
      end

      def channel_revenue
        @channel_revenue ||= credits_scope.group(:channel).sum(:revenue_credit)
      end

      def channel_impressions
        @channel_impressions ||= spend_scope.group(:channel).sum(:impressions)
      end

      def channel_clicks
        @channel_clicks ||= spend_scope.group(:channel).sum(:clicks)
      end

      def channel_platform_value
        @channel_platform_value ||= spend_scope.group(:channel)
          .sum(:platform_conversion_value_micros)
          .transform_values { |v| spend_in_units(v) }
      end
    end
  end
end
