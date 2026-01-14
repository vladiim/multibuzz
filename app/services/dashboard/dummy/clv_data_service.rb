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
        # "Smiling curve" - revenue per customer by lifecycle month
        # High month 1 (initial purchase), dip months 2-6 (churn), rise months 7-12 (loyal customers)
        {
          months: (0..12).to_a,
          revenue_per_customer: [
            89.50,  # M0: First purchase
            12.30,  # M1: Drop-off begins
            8.70,   # M2
            7.20,   # M3
            6.80,   # M4
            7.10,   # M5: Slight uptick
            9.40,   # M6: Returning customers
            14.20,  # M7
            18.60,  # M8
            22.30,  # M9
            26.80,  # M10
            31.40,  # M11
            38.20   # M12: Loyal customer peak
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
