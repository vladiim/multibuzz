# frozen_string_literal: true

module SpendIntelligence
  module Queries
    # Per-channel "what the ad platform reports" vs "what mbuzz attributes via the
    # selected model". Surfaces the gap (and percent) the dashboard renders as the
    # headline MTA pitch. Platform revenue is model-agnostic; attributed revenue
    # is single-model — instantiate one per attribution model.
    class PlatformVsAttributedQuery
      MICRO_UNIT = AdSpendRecord::MICRO_UNIT

      def initialize(spend_scope:, credits_scope:)
        @spend_scope = spend_scope
        @credits_scope = credits_scope
      end

      def by_channel
        @by_channel ||= channels.each_with_object({}) do |channel, acc|
          acc[channel] = entry_for(platform_revenue_by_channel[channel] || 0, attributed_revenue_by_channel[channel] || 0)
        end
      end

      def totals
        entry_for(total_platform_revenue, total_attributed_revenue)
      end

      def total_platform_revenue
        @total_platform_revenue ||= platform_revenue_by_channel.values.sum.to_f
      end

      def total_attributed_revenue
        @total_attributed_revenue ||= attributed_revenue_by_channel.values.sum.to_f
      end

      private

      attr_reader :spend_scope, :credits_scope

      def channels
        (platform_revenue_by_channel.keys + attributed_revenue_by_channel.keys).uniq
      end

      def entry_for(platform, attributed)
        gap = (attributed.to_f - platform.to_f).round(2)
        {
          platform_revenue: platform.to_f.round(2),
          gap: gap,
          gap_pct: gap_pct(platform, gap)
        }
      end

      def gap_pct(platform, gap)
        return nil unless platform.to_f.positive?

        ((gap / platform) * 100).round(1)
      end

      def platform_revenue_by_channel
        @platform_revenue_by_channel ||= spend_scope.group(:channel)
          .sum(:platform_conversion_value_micros)
          .transform_values { |micros| (micros.to_d / MICRO_UNIT).to_f }
      end

      def attributed_revenue_by_channel
        @attributed_revenue_by_channel ||= credits_scope.group(:channel)
          .sum(:revenue_credit)
          .transform_values(&:to_f)
      end
    end
  end
end
