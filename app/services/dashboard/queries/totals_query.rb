module Dashboard
  module Queries
    class TotalsQuery
      def initialize(scope, prior_scope: nil)
        @scope = scope
        @prior_scope = prior_scope
      end

      def call
        {
          conversions: sum_credits,
          revenue: sum_revenue,
          conversion_rate: nil, # TODO: requires visitor data
          aov: calculate_aov,
          prior_period: prior_period_data
        }
      end

      private

      attr_reader :scope, :prior_scope

      def sum_credits
        scope.sum(:credit).to_f
      end

      def sum_revenue
        scope.sum(:revenue_credit).to_f
      end

      def calculate_aov
        return nil if sum_credits.zero?

        (sum_revenue / sum_credits).round(2)
      end

      def prior_period_data
        return empty_prior_period unless prior_scope

        {
          conversions: prior_scope.sum(:credit).to_f,
          revenue: prior_scope.sum(:revenue_credit).to_f,
          conversion_rate: nil,
          aov: nil
        }
      end

      def empty_prior_period
        { conversions: 0, revenue: 0, conversion_rate: nil, aov: nil }
      end
    end
  end
end
