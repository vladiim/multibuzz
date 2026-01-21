module Dashboard
  module Queries
    class CohortAnalysisQuery
      MAX_MONTHS_SINCE_ACQUISITION = 12

      def initialize(account:, acquisition_conversions:, attribution_model: nil, test_mode: false)
        @account = account
        @acquisition_conversions = acquisition_conversions
        @attribution_model = attribution_model
        @test_mode = test_mode
      end

      def call
        return [] if acquisition_conversions.empty?

        cohorts_with_ltv
      end

      private

      attr_reader :account, :acquisition_conversions, :test_mode

      def cohorts_with_ltv
        cohort_groups.map { |cohort_month, identity_ids| build_cohort_row(cohort_month, identity_ids) }
          .sort_by { |row| row[:cohort] }
      end

      def build_cohort_row(cohort_month, identity_ids)
        {
          cohort: cohort_month,
          customers: identity_ids.size,
          months: months_since_acquisition_data(cohort_month, identity_ids)
        }
      end

      def months_since_acquisition_data(cohort_month, identity_ids)
        (0..MAX_MONTHS_SINCE_ACQUISITION).map do |month_offset|
          {
            month: month_offset,
            cumulative_ltv: cumulative_ltv_for_period(cohort_month, identity_ids, month_offset)
          }
        end
      end

      def cumulative_ltv_for_period(cohort_month, identity_ids, month_offset)
        period_end = cohort_month.beginning_of_month + (month_offset + 1).months
        return nil if period_end > Time.current

        identity_ids
          .then { |ids| revenue_before_date(ids, period_end) }
          .then { |revenue| average_per_customer(revenue, identity_ids.size) }
      end

      def revenue_before_date(identity_ids, cutoff_date)
        identity_ids
          .flat_map { |id| conversions_by_identity[id] || [] }
          .select { |c| c[:converted_at] < cutoff_date }
          .sum { |c| c[:revenue] || 0 }
      end

      def average_per_customer(revenue, customer_count)
        return 0 unless customer_count.positive?

        (revenue / customer_count).round(2)
      end

      def conversions_by_identity
        @conversions_by_identity ||= all_customer_conversions
          .group_by { |c| c[:identity_id] }
      end

      def all_customer_conversions
        @all_customer_conversions ||= account.conversions
          .where(identity_id: acquired_identity_ids)
          .then { |scope| test_mode ? scope.test_data : scope.production }
          .pluck(:identity_id, :converted_at, :revenue)
          .map { |id, time, rev| { identity_id: id, converted_at: time, revenue: rev } }
      end

      def cohort_groups
        @cohort_groups ||= identity_acquisition_dates
          .group_by { |_id, date| date.beginning_of_month }
          .transform_values { |pairs| pairs.map(&:first) }
      end

      def identity_acquisition_dates
        @identity_acquisition_dates ||= acquisition_conversions
          .pluck(:identity_id, :converted_at)
      end

      def acquired_identity_ids
        @acquired_identity_ids ||= acquisition_conversions.pluck(:identity_id).compact
      end
    end
  end
end
