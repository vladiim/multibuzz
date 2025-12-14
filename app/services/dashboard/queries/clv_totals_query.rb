module Dashboard
  module Queries
    class ClvTotalsQuery
      def initialize(account:, identity_ids:, test_mode: false)
        @account = account
        @identity_ids = identity_ids
        @test_mode = test_mode
      end

      def call
        return empty_totals if identity_ids.empty?

        {
          clv: clv,
          customers: customers,
          purchases: purchases,
          revenue: revenue,
          avg_duration: avg_duration,
          repurchase_frequency: repurchase_frequency
        }
      end

      private

      attr_reader :account, :identity_ids, :test_mode

      def clv
        customers.positive? ? (revenue / customers).round(2) : 0
      end

      def customers
        @customers ||= identity_ids.size
      end

      def purchases
        @purchases ||= customer_conversions.count
      end

      def revenue
        @revenue ||= customer_conversions.sum(:revenue).to_f
      end

      def avg_duration
        durations = customer_lifespans.compact
        return 0 if durations.empty?

        (durations.sum / durations.size).round
      end

      def repurchase_frequency
        customers.positive? ? (purchases.to_f / customers).round(1) : 0
      end

      def customer_conversions
        @customer_conversions ||= account.conversions
          .where(identity_id: identity_ids)
          .then { |scope| test_mode ? scope.test_data : scope.production }
      end

      def customer_lifespans
        @customer_lifespans ||= customer_conversions
          .group(:identity_id)
          .pluck(
            Arel.sql("EXTRACT(DAY FROM (MAX(converted_at) - MIN(converted_at)))")
          )
      end

      def empty_totals
        {
          clv: 0,
          customers: 0,
          purchases: 0,
          revenue: 0,
          avg_duration: 0,
          repurchase_frequency: 0
        }
      end
    end
  end
end
