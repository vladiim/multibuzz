module Dashboard
  module Queries
    class TotalsQuery
      def initialize(scope, prior_scope: nil, sessions_scope: nil, prior_sessions_scope: nil)
        @scope = scope
        @prior_scope = prior_scope
        @sessions_scope = sessions_scope
        @prior_sessions_scope = prior_sessions_scope
      end

      def call
        {
          conversions: sum_credits,
          revenue: sum_revenue,
          conversion_rate: calculate_conversion_rate,
          aov: calculate_aov,
          prior_period: prior_period_data
        }
      end

      private

      attr_reader :scope, :prior_scope, :sessions_scope, :prior_sessions_scope

      def sum_credits
        @sum_credits ||= scope.sum(:credit).to_f
      end

      def sum_revenue
        @sum_revenue ||= scope.sum(:revenue_credit).to_f
      end

      def sessions_count
        @sessions_count ||= sessions_scope&.count || 0
      end

      def calculate_conversion_rate
        return nil if sessions_scope.nil?
        return nil if sessions_count.zero?
        return nil if sum_credits.zero?

        ((sum_credits / sessions_count) * 100).round(1)
      end

      def calculate_aov
        return nil if sum_credits.zero?

        (sum_revenue / sum_credits).round(2)
      end

      def prior_period_data
        return empty_prior_period unless prior_scope

        prior_conversions = prior_scope.sum(:credit).to_f
        prior_sessions = prior_sessions_scope&.count || 0
        prior_rate = prior_sessions.positive? ? ((prior_conversions / prior_sessions) * 100).round(1) : nil

        {
          conversions: prior_conversions,
          revenue: prior_scope.sum(:revenue_credit).to_f,
          conversion_rate: prior_rate,
          aov: nil
        }
      end

      def empty_prior_period
        { conversions: 0, revenue: 0, conversion_rate: nil, aov: nil }
      end
    end
  end
end
