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
            prior_period: {
              conversions: 2120,
              revenue: 135_400,
              conversion_rate: 2.9,
              aov: 63.87
            }
          },
          by_channel: channel_data,
          time_series: time_series_data,
          top_campaigns: top_campaigns_data
        }
      end

      def channel_data
        [
          { channel: Channels::PAID_SEARCH, credits: 450, revenue: 27_000, percentage: 18.9 },
          { channel: Channels::ORGANIC_SEARCH, credits: 380, revenue: 22_800, percentage: 16.0 },
          { channel: Channels::EMAIL, credits: 320, revenue: 19_200, percentage: 13.4 },
          { channel: Channels::PAID_SOCIAL, credits: 280, revenue: 16_800, percentage: 11.8 },
          { channel: Channels::DIRECT, credits: 250, revenue: 15_000, percentage: 10.5 },
          { channel: Channels::REFERRAL, credits: 220, revenue: 13_200, percentage: 9.2 },
          { channel: Channels::ORGANIC_SOCIAL, credits: 180, revenue: 10_800, percentage: 7.6 },
          { channel: Channels::DISPLAY, credits: 150, revenue: 9_000, percentage: 6.3 },
          { channel: Channels::AFFILIATE, credits: 100, revenue: 6_000, percentage: 4.2 },
          { channel: Channels::VIDEO, credits: 52, revenue: 3_120, percentage: 2.2 }
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
            {
              channel: channel,
              data: dates.map { |_| rand(10..25) + (channel == Channels::PAID_SEARCH ? 5 : 0) }
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
    end
  end
end
