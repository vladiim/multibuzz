# frozen_string_literal: true

module Dashboard
  module Dummy
    class ClvDataService < ApplicationService
      private

      def run
        success_result(data: clv_data)
      end

      def clv_data
        {
          totals: totals,
          by_channel: by_channel,
          smiling_curve: smiling_curve,
          cohort_analysis: cohort_analysis,
          coverage: coverage,
          has_data: true
        }
      end

      def totals
        {
          clv: 247.32,
          customers: 1_847,
          purchases: 4_892,
          revenue: 456_798,
          avg_duration: 127,
          repurchase_frequency: 2.65
        }
      end

      def by_channel
        # CLV by acquisition channel - shows where high-value customers come from
        # Referral and Organic tend to have higher CLV than Paid
        [
          { channel: Channels::REFERRAL, clv: 412.50, customers: 186, revenue: 76_725 },
          { channel: Channels::ORGANIC_SEARCH, clv: 328.40, customers: 412, revenue: 135_301 },
          { channel: Channels::EMAIL, clv: 295.20, customers: 287, revenue: 84_722 },
          { channel: Channels::ORGANIC_SOCIAL, clv: 267.80, customers: 156, revenue: 41_777 },
          { channel: Channels::DIRECT, clv: 241.60, customers: 298, revenue: 71_997 },
          { channel: Channels::PAID_SEARCH, clv: 189.30, customers: 312, revenue: 59_062 },
          { channel: Channels::PAID_SOCIAL, clv: 156.40, customers: 196, revenue: 30_654 }
        ]
      end

      def smiling_curve
        # "Smiling curve" - revenue per customer by lifecycle month, broken down by acquisition channel
        # High month 0 (initial purchase), dip months 1-5 (churn), rise months 6-12 (loyal customers)
        # Different channels show different retention/loyalty patterns
        {
          months: (0..12).to_a,
          series: [
            {
              channel: Channels::REFERRAL,
              data: [ 95.20, 18.40, 14.60, 12.80, 12.20, 13.50, 16.80, 22.40, 28.60, 35.20, 42.80, 51.40, 62.30 ]
            },
            {
              channel: Channels::ORGANIC_SEARCH,
              data: [ 89.50, 12.30, 8.70, 7.20, 6.80, 7.10, 9.40, 14.20, 18.60, 22.30, 26.80, 31.40, 38.20 ]
            },
            {
              channel: Channels::EMAIL,
              data: [ 82.40, 14.80, 10.20, 8.40, 7.90, 8.60, 11.20, 16.40, 21.80, 27.60, 33.80, 40.20, 48.60 ]
            },
            {
              channel: Channels::PAID_SEARCH,
              data: [ 78.30, 8.20, 5.40, 4.20, 3.80, 4.10, 5.60, 8.20, 10.80, 13.40, 16.20, 19.40, 23.80 ]
            },
            {
              channel: Channels::DIRECT,
              data: [ 72.60, 10.40, 7.20, 5.80, 5.40, 5.90, 7.80, 11.60, 15.20, 18.80, 22.60, 27.20, 32.80 ]
            }
          ]
        }
      end

      def cohort_analysis
        # Cohort LTV progression - shows how customer value grows over time
        # Each cohort row shows cumulative LTV at months 0-12
        base_date = Date.current.beginning_of_month

        [
          cohort_row(base_date - 12.months, 156, [ 92, 108, 124, 142, 158, 176, 195, 218, 242, 268, 296, 328, 362 ]),
          cohort_row(base_date - 11.months, 142, [ 88, 102, 118, 135, 151, 168, 186, 207, 230, 254, 281, 310, nil ]),
          cohort_row(base_date - 10.months, 168, [ 94, 110, 127, 146, 163, 181, 201, 224, 249, 276, 305, nil, nil ]),
          cohort_row(base_date - 9.months, 134, [ 86, 100, 115, 132, 147, 164, 182, 203, 225, 249, nil, nil, nil ]),
          cohort_row(base_date - 8.months, 189, [ 91, 106, 122, 140, 156, 174, 193, 215, 239, nil, nil, nil, nil ]),
          cohort_row(base_date - 7.months, 162, [ 90, 105, 121, 139, 155, 172, 191, 213, nil, nil, nil, nil, nil ]),
          cohort_row(base_date - 6.months, 178, [ 93, 108, 125, 143, 160, 178, 197, nil, nil, nil, nil, nil, nil ]),
          cohort_row(base_date - 5.months, 145, [ 87, 101, 117, 134, 150, 167, nil, nil, nil, nil, nil, nil, nil ]),
          cohort_row(base_date - 4.months, 198, [ 95, 111, 128, 147, 164, nil, nil, nil, nil, nil, nil, nil, nil ]),
          cohort_row(base_date - 3.months, 167, [ 89, 104, 120, 138, nil, nil, nil, nil, nil, nil, nil, nil, nil ]),
          cohort_row(base_date - 2.months, 184, [ 92, 107, 124, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil ]),
          cohort_row(base_date - 1.month, 159, [ 88, 103, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil ]),
          cohort_row(base_date, 165, [ 91, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil ])
        ]
      end

      def coverage
        # Shows what % of conversions have identity resolution
        {
          total: 4_892,
          identified: 4_156,
          percentage: 84.9
        }
      end

      private

      def cohort_row(cohort_date, customers, monthly_values)
        {
          cohort: cohort_date.strftime("%b %Y"),
          customers: customers,
          months: monthly_values.each_with_index.map do |value, index|
            { month: index, cumulative_ltv: value }
          end
        }
      end
    end
  end
end
