module Dashboard
  module Queries
    class SmilingCurveQuery
      MAX_LIFECYCLE_MONTHS = 12

      def initialize(account:, acquisition_conversions:, attribution_model: nil, test_mode: false)
        @account = account
        @acquisition_conversions = acquisition_conversions
        @attribution_model = attribution_model
        @test_mode = test_mode
      end

      def call
        return empty_result if acquisition_conversions.empty?

        {
          months: (0..MAX_LIFECYCLE_MONTHS).to_a,
          series: channel_series
        }
      end

      private

      attr_reader :account, :acquisition_conversions, :attribution_model, :test_mode

      def empty_result
        { months: [], series: [] }
      end

      def channel_series
        channel_identity_acquisitions.map do |channel, identity_acquisitions|
          {
            channel: channel,
            data: (0..MAX_LIFECYCLE_MONTHS).map { |month| average_revenue_for_channel(identity_acquisitions, month) }
          }
        end
      end

      def average_revenue_for_channel(identity_acquisitions, month)
        revenues = identity_acquisitions.filter_map do |identity_id, acquisition_date|
          revenue_for_lifecycle_month(identity_id, acquisition_date, month)
        end

        return 0.0 if revenues.empty?

        (revenues.sum / revenues.size).round(2).to_f
      end

      def revenue_for_lifecycle_month(identity_id, acquisition_date, month)
        # M0 = acquisition month, M1 = 1 month later, etc.
        month_start = acquisition_date.beginning_of_month + month.months
        month_end = month_start + 1.month

        return nil if month_start > Time.current

        conversions_for_identity(identity_id)
          .select { |c| c[:converted_at] >= month_start && c[:converted_at] < month_end }
          .sum { |c| c[:revenue] || 0 }
      end

      def conversions_for_identity(identity_id)
        @conversions_by_identity ||= all_customer_conversions
          .group_by { |c| c[:identity_id] }

        @conversions_by_identity[identity_id] || []
      end

      def all_customer_conversions
        @all_customer_conversions ||= account.conversions
          .where(identity_id: acquired_identity_ids)
          .then { |scope| test_mode ? scope.test_data : scope.production }
          .pluck(:identity_id, :converted_at, :revenue)
          .map { |id, time, rev| { identity_id: id, converted_at: time, revenue: rev } }
      end

      def channel_identity_acquisitions
        @channel_identity_acquisitions ||= acquisition_credits
          .group_by { |c| c[:channel] }
          .transform_values { |credits| credits.to_h { |c| [c[:identity_id], c[:acquisition_date]] } }
      end

      def acquisition_credits
        @acquisition_credits ||= AttributionCredit
          .joins(:conversion)
          .where(conversion_id: acquisition_conversions.pluck(:id))
          .where(attribution_model: primary_model)
          .pluck(:channel, "conversions.identity_id", "conversions.converted_at")
          .map { |channel, identity_id, converted_at| { channel: channel, identity_id: identity_id, acquisition_date: converted_at } }
      end

      def acquired_identity_ids
        @acquired_identity_ids ||= acquisition_conversions.pluck(:identity_id).compact
      end

      def primary_model
        @primary_model ||= attribution_model ||
          account.attribution_models.active.find_by(is_default: true) ||
          account.attribution_models.active.first
      end
    end
  end
end
