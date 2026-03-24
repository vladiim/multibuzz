# frozen_string_literal: true

module Dashboard
  module Dummy
    class SpendDataService
      def call
        { success: true, data: data }
      end

      private

      def data
        {
          totals: totals,
          by_channel: channel_data,
          time_series: time_series_data,
          by_hour: hourly_data,
          by_device: device_data,
          payback: payback_data,
          recommendations: recommendations_data
        }
      end

      # --- Totals ---

      def totals
        {
          blended_roas: 3.2,
          total_spend: 24_500,
          total_spend_micros: 24_500_000_000,
          attributed_revenue: 78_400,
          currency: "USD",
          ncac: 47,
          mer: 4.1
        }
      end

      # --- Channels ---

      def channel_data
        [
          { channel: "paid_search", spend_micros: 12_200_000_000, attributed_revenue: 45_200,
            roas: 3.7, platform_roas: 5.1, impressions: 245_000, clicks: 8_900 },
          { channel: "paid_social", spend_micros: 6_800_000_000, attributed_revenue: 18_600,
            roas: 2.7, platform_roas: 4.2, impressions: 520_000, clicks: 6_400 },
          { channel: "display", spend_micros: 3_200_000_000, attributed_revenue: 8_960,
            roas: 2.8, platform_roas: 3.8, impressions: 890_000, clicks: 3_100 },
          { channel: "video", spend_micros: 1_500_000_000, attributed_revenue: 3_840,
            roas: 2.6, platform_roas: 3.5, impressions: 180_000, clicks: 1_200 },
          { channel: "affiliate", spend_micros: 800_000_000, attributed_revenue: 1_800,
            roas: 2.3, platform_roas: nil, impressions: 45_000, clicks: 680 }
        ]
      end

      # --- Time Series ---

      def time_series_data
        base_date = Date.current - 29.days
        (0..29).map { |i| build_day_entry(base_date + i.days, i) }
      end

      def build_day_entry(date, index)
        spend = daily_spend(date, index)
        revenue = (spend * (2.8 + Math.sin(index * 0.5) * 0.6)).round

        { date: date.to_s, spend: spend, spend_micros: spend * 1_000_000,
          revenue: revenue, roas: (revenue.to_f / spend).round(1) }
      end

      def daily_spend(date, index)
        base = (date.saturday? || date.sunday?) ? 650 : 850
        base + ((Math.sin(index * 0.3) * 120) + (index * 3)).round
      end

      # --- Hourly ---

      def hourly_data
        hourly_pattern = [
          80, 60, 40, 30, 25, 35,
          120, 280, 520, 780, 850, 900,
          920, 880, 840, 790, 720, 650,
          580, 480, 380, 280, 180, 120
        ]

        hourly_pattern.each_with_index.map do |base, hour|
          { hour: hour, spend_micros: base * 1_000_000 }
        end
      end

      # --- Device ---

      def device_data
        [
          { device: "DESKTOP", spend_micros: 11_800_000_000, impressions: 780_000, clicks: 8_600, cpc_micros: 1_372_093 },
          { device: "MOBILE", spend_micros: 10_500_000_000, impressions: 820_000, clicks: 9_200, cpc_micros: 1_141_304 },
          { device: "TABLET", spend_micros: 2_200_000_000, impressions: 280_000, clicks: 2_480, cpc_micros: 887_097 }
        ]
      end

      # --- Payback Period ---

      def payback_data
        [
          { channel: "paid_search", ncac: 47, customers: 312, payback_months: 2,
            clv_curve: clv_curve([ 22, 38, 51, 60, 67, 72, 76, 79, 81, 83, 84, 85 ]) },
          { channel: "paid_social", ncac: 62, customers: 184, payback_months: 5,
            clv_curve: clv_curve([ 10, 19, 28, 36, 44, 51, 57, 63, 68, 72, 75, 78 ]) },
          { channel: "display", ncac: 84, customers: 68, payback_months: 7,
            clv_curve: clv_curve([ 8, 15, 22, 29, 36, 43, 50, 57, 63, 69, 74, 78 ]) },
          { channel: "video", ncac: 71, customers: 42, payback_months: 6,
            clv_curve: clv_curve([ 9, 17, 25, 33, 41, 48, 55, 61, 66, 71, 75, 78 ]) },
          { channel: "affiliate", ncac: 38, customers: 24, payback_months: 1,
            clv_curve: clv_curve([ 32, 48, 58, 65, 70, 74, 77, 79, 81, 82, 83, 84 ]) }
        ]
      end

      def clv_curve(values)
        values.each_with_index.map { |v, i| { month: i, cumulative_clv: v } }
      end

      # --- Recommendations (Scale / Maintain / Reduce) ---

      def recommendations_data
        [
          { channel: "paid_search", action: "scale", roas: 3.7, marginal_roas: 2.8,
            change_amount: 3_000, rationale: "Still climbing the curve. Room to grow." },
          { channel: "affiliate", action: "scale", roas: 2.3, marginal_roas: 1.9,
            change_amount: 500, rationale: "High-intent traffic with low NCAC. Scale steadily." },
          { channel: "paid_social", action: "maintain", roas: 2.7, marginal_roas: 1.2,
            change_amount: 0, rationale: "Approaching saturation. Current spend is optimal." },
          { channel: "video", action: "maintain", roas: 2.6, marginal_roas: 1.1,
            change_amount: 0, rationale: "Solid returns but limited headroom at current spend." },
          { channel: "display", action: "reduce", roas: 2.8, marginal_roas: 0.6,
            change_amount: -500, rationale: "Past diminishing returns. Shift budget to search." }
        ]
      end
    end
  end
end
