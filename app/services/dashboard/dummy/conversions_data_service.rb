module Dashboard
  module Dummy
    class ConversionsDataService < ApplicationService
      private

      def run
        success_result(data: conversions_data)
      end

      def conversions_data
        {
          totals: {
            conversions: 2382,
            revenue: 147_230,
            conversion_rate: 3.2,
            aov: 61.81,
            avg_days_to_convert: 4.2,
            avg_channels_to_convert: 2.8,
            avg_visits_to_convert: 5.1,
            prior_period: {
              conversions: 2120,
              revenue: 135_400,
              conversion_rate: 2.9,
              aov: 63.87
            }
          },
          by_channel: channel_data,
          by_conversion_name: by_conversion_name_data,
          time_series: time_series_data,
          top_campaigns: top_campaigns_data
        }
      end

      def channel_data
        [
          { channel: Channels::PAID_SEARCH, credits: 450, revenue: 27_000, aov: 60.00, percentage: 18.9, avg_channels: 3.2, avg_visits: 6.1, avg_days: 3.8 },
          { channel: Channels::ORGANIC_SEARCH, credits: 380, revenue: 22_800, aov: 60.00, percentage: 16.0, avg_channels: 2.8, avg_visits: 5.4, avg_days: 4.2 },
          { channel: Channels::EMAIL, credits: 320, revenue: 22_400, aov: 70.00, percentage: 13.4, avg_channels: 2.5, avg_visits: 4.8, avg_days: 3.1 },
          { channel: Channels::PAID_SOCIAL, credits: 280, revenue: 15_400, aov: 55.00, percentage: 11.8, avg_channels: 3.1, avg_visits: 5.9, avg_days: 4.5 },
          { channel: Channels::DIRECT, credits: 250, revenue: 18_750, aov: 75.00, percentage: 10.5, avg_channels: 1.8, avg_visits: 3.2, avg_days: 2.1 },
          { channel: Channels::REFERRAL, credits: 220, revenue: 14_300, aov: 65.00, percentage: 9.2, avg_channels: 2.4, avg_visits: 4.1, avg_days: 3.5 },
          { channel: Channels::ORGANIC_SOCIAL, credits: 180, revenue: 9_000, aov: 50.00, percentage: 7.6, avg_channels: 2.9, avg_visits: 5.2, avg_days: 4.8 },
          { channel: Channels::DISPLAY, credits: 150, revenue: 8_250, aov: 55.00, percentage: 6.3, avg_channels: 3.4, avg_visits: 6.8, avg_days: 5.2 },
          { channel: Channels::AFFILIATE, credits: 100, revenue: 7_200, aov: 72.00, percentage: 4.2, avg_channels: 2.2, avg_visits: 3.9, avg_days: 2.8 },
          { channel: Channels::VIDEO, credits: 52, revenue: 2_340, aov: 45.00, percentage: 2.2, avg_channels: 3.6, avg_visits: 7.2, avg_days: 5.8 }
        ]
      end

      def time_series_data
        # Last 30 days of data for top 5 channels
        dates = (29.days.ago.to_date..Date.current).to_a
        top_channels = [ Channels::PAID_SEARCH, Channels::ORGANIC_SEARCH, Channels::EMAIL,
                        Channels::PAID_SOCIAL, Channels::DIRECT ]

        {
          dates: dates.map(&:iso8601),
          series: top_channels.map do |channel|
            base_credits = channel == Channels::PAID_SEARCH ? 20 : 15
            {
              channel: channel,
              data: dates.map do |_|
                credits = rand(10..25) + (channel == Channels::PAID_SEARCH ? 5 : 0)
                aov = rand(45..75)
                {
                  credits: credits,
                  revenue: credits * aov,
                  aov: aov,
                  avg_channels: (rand(20..40) / 10.0).round(1),
                  avg_visits: (rand(30..70) / 10.0).round(1),
                  avg_days: (rand(20..60) / 10.0).round(1)
                }
              end
            }
          end
        }
      end

      def top_campaigns_data
        {
          Channels::PAID_SEARCH => [
            { name: "Brand - Exact Match", conversions: 180, revenue: 10_800 },
            { name: "Non-Brand - Generic", conversions: 120, revenue: 7_200 },
            { name: "Competitor Targeting", conversions: 85, revenue: 5_100 },
            { name: "Remarketing - Search", conversions: 65, revenue: 3_900 }
          ],
          Channels::ORGANIC_SEARCH => [
            { name: "Blog Content", conversions: 150, revenue: 9_000 },
            { name: "Product Pages", conversions: 130, revenue: 7_800 },
            { name: "Landing Pages", conversions: 100, revenue: 6_000 }
          ],
          Channels::EMAIL => [
            { name: "Welcome Series", conversions: 120, revenue: 7_200 },
            { name: "Abandoned Cart", conversions: 95, revenue: 5_700 },
            { name: "Newsletter", conversions: 65, revenue: 3_900 },
            { name: "Win-back Campaign", conversions: 40, revenue: 2_400 }
          ]
        }
      end

      def by_conversion_name_data
        [
          {
            channel: "Purchase",
            by_channel: [
              { channel: Channels::PAID_SEARCH, credits: 320, revenue: 19_200, aov: 60.00, avg_channels: 3.2, avg_visits: 6.1, avg_days: 3.8 },
              { channel: Channels::ORGANIC_SEARCH, credits: 280, revenue: 16_800, aov: 60.00, avg_channels: 2.8, avg_visits: 5.4, avg_days: 4.2 },
              { channel: Channels::EMAIL, credits: 240, revenue: 16_800, aov: 70.00, avg_channels: 2.5, avg_visits: 4.8, avg_days: 3.1 },
              { channel: Channels::PAID_SOCIAL, credits: 180, revenue: 9_900, aov: 55.00, avg_channels: 3.1, avg_visits: 5.9, avg_days: 4.5 },
              { channel: Channels::DIRECT, credits: 160, revenue: 12_000, aov: 75.00, avg_channels: 1.8, avg_visits: 3.2, avg_days: 2.1 }
            ]
          },
          {
            channel: "Signup",
            by_channel: [
              { channel: Channels::ORGANIC_SEARCH, credits: 100, revenue: 0, aov: 0, avg_channels: 2.4, avg_visits: 4.8, avg_days: 3.5 },
              { channel: Channels::PAID_SOCIAL, credits: 80, revenue: 0, aov: 0, avg_channels: 2.9, avg_visits: 5.2, avg_days: 4.1 },
              { channel: Channels::REFERRAL, credits: 70, revenue: 0, aov: 0, avg_channels: 2.2, avg_visits: 3.9, avg_days: 2.8 },
              { channel: Channels::DIRECT, credits: 60, revenue: 0, aov: 0, avg_channels: 1.6, avg_visits: 2.8, avg_days: 1.9 },
              { channel: Channels::PAID_SEARCH, credits: 50, revenue: 0, aov: 0, avg_channels: 3.0, avg_visits: 5.5, avg_days: 3.2 }
            ]
          },
          {
            channel: "Trial Start",
            by_channel: [
              { channel: Channels::PAID_SEARCH, credits: 80, revenue: 0, aov: 0, avg_channels: 3.4, avg_visits: 6.8, avg_days: 4.2 },
              { channel: Channels::EMAIL, credits: 60, revenue: 0, aov: 0, avg_channels: 2.3, avg_visits: 4.2, avg_days: 2.8 },
              { channel: Channels::ORGANIC_SEARCH, credits: 50, revenue: 0, aov: 0, avg_channels: 2.6, avg_visits: 5.0, avg_days: 3.8 },
              { channel: Channels::DIRECT, credits: 30, revenue: 0, aov: 0, avg_channels: 1.5, avg_visits: 2.5, avg_days: 1.5 }
            ]
          }
        ]
      end
    end
  end
end
