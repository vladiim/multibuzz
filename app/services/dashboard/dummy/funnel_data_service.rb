module Dashboard
  module Dummy
    class FunnelDataService < ApplicationService
      private

      def run
        success_result(data: funnel_data)
      end

      def funnel_data
        {
          stages: [
            {
              stage: "Visits",
              total: 349_402,
              by_channel: channel_breakdown([ 87_350, 69_880, 52_410, 41_928, 38_434, 27_952, 17_470, 10_482, 2_794, 702, 0 ]),
              conversion_rate: nil
            },
            {
              stage: "Add to Cart",
              total: 37_145,
              by_channel: channel_breakdown([ 9_286, 7_429, 5_572, 4_457, 4_086, 2_972, 1_857, 1_114, 297, 75, 0 ]),
              conversion_rate: 10.6
            },
            {
              stage: "Checkout Started",
              total: 5_504,
              by_channel: channel_breakdown([ 1_376, 1_101, 825, 660, 605, 440, 275, 165, 44, 13, 0 ]),
              conversion_rate: 14.8
            },
            {
              stage: "Purchase",
              total: 2_382,
              by_channel: channel_breakdown([ 596, 476, 357, 286, 262, 190, 119, 71, 19, 6, 0 ]),
              conversion_rate: 43.3
            }
          ]
        }
      end

      def channel_breakdown(values)
        Channels::ALL.zip(values).to_h
      end
    end
  end
end
