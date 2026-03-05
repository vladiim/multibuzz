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
          by_device: device_data
        }
      end

      def totals
        {
          blended_roas: 3.2,
          total_spend: 24_500,
          total_spend_micros: 24_500_000_000,
          attributed_revenue: 78_400,
          currency: "USD"
        }
      end

      def channel_data
        [
          { channel: "paid_search", spend_micros: 12_200_000_000, attributed_revenue: 45_200, roas: 3.7, impressions: 245_000, clicks: 8_900, cpc_micros: 1_370_787 },
          { channel: "paid_social", spend_micros: 6_800_000_000, attributed_revenue: 18_600, roas: 2.7, impressions: 520_000, clicks: 6_400, cpc_micros: 1_062_500 },
          { channel: "display", spend_micros: 3_200_000_000, attributed_revenue: 8_960, roas: 2.8, impressions: 890_000, clicks: 3_100, cpc_micros: 1_032_258 },
          { channel: "video", spend_micros: 1_500_000_000, attributed_revenue: 3_840, roas: 2.6, impressions: 180_000, clicks: 1_200, cpc_micros: 1_250_000 },
          { channel: "affiliate", spend_micros: 800_000_000, attributed_revenue: 1_800, roas: 2.3, impressions: 45_000, clicks: 680, cpc_micros: 1_176_471 }
        ]
      end

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

      def hourly_data
        # Peak spend during business hours, tapering off at night
        hourly_pattern = [
          80, 60, 40, 30, 25, 35,       # 0-5am
          120, 280, 520, 780, 850, 900,  # 6-11am
          920, 880, 840, 790, 720, 650,  # 12-5pm
          580, 480, 380, 280, 180, 120   # 6-11pm
        ]

        hourly_pattern.each_with_index.map do |base, hour|
          { hour: hour, spend_micros: base * 1_000_000 }
        end
      end

      def device_data
        [
          { device: "MOBILE", spend_micros: 10_500_000_000, impressions: 820_000, clicks: 9_200, cpc_micros: 1_141_304 },
          { device: "DESKTOP", spend_micros: 11_800_000_000, impressions: 780_000, clicks: 8_600, cpc_micros: 1_372_093 },
          { device: "TABLET", spend_micros: 2_200_000_000, impressions: 280_000, clicks: 2_480, cpc_micros: 887_097 }
        ]
      end
    end
  end
end
