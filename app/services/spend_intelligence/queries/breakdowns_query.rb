# frozen_string_literal: true

module SpendIntelligence
  module Queries
    class BreakdownsQuery
      MICRO_UNIT = AdSpendRecord::MICRO_UNIT

      def initialize(spend_scope:, credits_scope:)
        @spend_scope = spend_scope
        @credits_scope = credits_scope
      end

      def time_series
        daily_spend.keys.sort.map { |date| time_series_entry(date) }
      end

      def by_device
        device_aggregates
          .map { |row| device_entry(row) }
          .sort_by { |d| -(d[:spend_micros] || 0) }
      end

      def by_hour
        spend_scope.group(:spend_hour).sum(:spend_micros)
          .sort_by(&:first)
          .map { |hour, spend| { hour: hour, spend_micros: spend } }
      end

      private

      attr_reader :spend_scope, :credits_scope

      # --- Time Series ---

      def time_series_entry(date)
        spend = daily_spend[date] || 0
        revenue = (daily_revenue[date] || 0).to_f

        {
          date: date.to_s,
          spend_micros: spend,
          spend: spend_in_units(spend),
          revenue: revenue,
          roas: roas(spend, revenue)
        }
      end

      def daily_spend
        @daily_spend ||= spend_scope.group(:spend_date).sum(:spend_micros)
      end

      def daily_revenue
        @daily_revenue ||= credits_scope.joins(:conversion)
          .group(Arel.sql("DATE(conversions.converted_at)")).sum(:revenue_credit)
      end

      # --- Device ---

      def device_aggregates
        spend_scope.group(:device)
          .select("device, SUM(spend_micros) AS total_spend, SUM(impressions) AS total_impressions, SUM(clicks) AS total_clicks")
      end

      def device_entry(row)
        {
          device: row.device,
          spend_micros: row.total_spend,
          impressions: row.total_impressions,
          clicks: row.total_clicks,
          cpc_micros: row.total_clicks.positive? ? row.total_spend / row.total_clicks : nil
        }
      end

      # --- Helpers ---

      def roas(spend_micros, revenue)
        return nil unless spend_micros.positive?

        (revenue / spend_in_units(spend_micros)).round(2)
      end

      def spend_in_units(micros)
        micros.to_d / MICRO_UNIT
      end
    end
  end
end
