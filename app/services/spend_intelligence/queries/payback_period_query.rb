# frozen_string_literal: true

module SpendIntelligence
  module Queries
    class PaybackPeriodQuery
      MICRO_UNIT = AdSpendRecord::MICRO_UNIT
      MONTHS_TO_ANALYZE = 12
      DAYS_PER_MONTH = 30.44
      SECONDS_PER_MONTH = (DAYS_PER_MONTH * 86_400).round
      ZERO = 0

      def initialize(spend_scope:, account:, attribution_model:, test_mode: false)
        @spend_scope = spend_scope
        @account = account
        @attribution_model = attribution_model
        @test_mode = test_mode
      end

      def call
        return [] if acquisition_channels.empty?

        acquisition_channels
          .map { |channel| build_payback_row(channel) }
          .sort_by { |row| row[:payback_months] || Float::INFINITY }
      end

      private

      attr_reader :spend_scope, :account, :attribution_model, :test_mode

      def build_payback_row(channel)
        {
          channel: channel,
          ncac: ncac_for(channel),
          customers: acquisition_count_for(channel),
          payback_months: payback_months_for(channel),
          clv_curve: clv_curve_for(channel)
        }
      end

      # --- NCAC ---

      def ncac_for(channel)
        acquisition_count_for(channel).positive? ? (channel_spend_units(channel) / acquisition_count_for(channel)).round(2) : nil
      end

      def channel_spend_units(channel)
        (channel_spend[channel] || ZERO).to_d / MICRO_UNIT
      end

      def acquisition_count_for(channel)
        acquisition_counts[channel] || ZERO
      end

      # --- Payback ---

      def payback_months_for(channel)
        ncac_for(channel)&.then { |ncac| ncac.zero? ? ZERO : first_month_exceeding(clv_curve_for(channel), ncac) }
      end

      def first_month_exceeding(curve, threshold)
        curve.find { |point| point[:cumulative_clv] >= threshold }&.dig(:month)
      end

      # --- CLV curve ---

      def clv_curve_for(channel)
        @clv_curves ||= {}
        @clv_curves[channel] ||= build_clv_curve(channel)
      end

      def build_clv_curve(channel)
        return [] unless customer_count_for(channel).positive?

        cumulative_curve(monthly_per_customer(channel))
      end

      def monthly_per_customer(channel)
        (0...MONTHS_TO_ANALYZE).map { |month| monthly_customer_revenue(channel, month) }
      end

      def monthly_customer_revenue(channel, month)
        (revenue_by_month_for(channel)[month] || ZERO).to_f / customer_count_for(channel)
      end

      def cumulative_curve(monthly_values)
        monthly_values.each_with_object([]) do |revenue, curve|
          prior = curve.last&.dig(:cumulative_clv) || ZERO
          curve << { month: curve.size, cumulative_clv: (prior + revenue).round(2) }
        end
      end

      def customer_count_for(channel)
        (channel_identities[channel] || []).size
      end

      # --- Acquisition channels ---

      def acquisition_channels
        @acquisition_channels ||= acquisition_counts.keys
      end

      # --- Data sources ---

      def channel_spend
        @channel_spend ||= spend_scope.group(:channel).sum(:spend_micros)
      end

      def acquisition_counts
        @acquisition_counts ||= acquisition_credits
          .group(:channel)
          .distinct
          .count(:conversion_id)
      end

      def channel_identities
        @channel_identities ||= acquisition_credits
          .joins(:conversion)
          .where.not(conversions: { identity_id: nil })
          .pluck(:channel, "conversions.identity_id")
          .group_by(&:first)
          .transform_values { |pairs| pairs.map(&:last).uniq }
      end

      def revenue_by_month_for(channel)
        @revenue_by_month ||= {}
        @revenue_by_month[channel] ||= revenue_by_month(channel_identities[channel] || [])
      end

      def acquisition_credits
        @acquisition_credits ||= account
          .attribution_credits
          .joins(:conversion)
          .where(attribution_model: attribution_model)
          .where(conversions: { is_acquisition: true })
          .then { |scope| test_mode ? scope.test_data : scope.production }
      end

      def revenue_by_month(identity_ids)
        account.conversions
          .where(identity_id: identity_ids)
          .then { |scope| test_mode ? scope.test_data : scope.production }
          .group(month_bucket_sql)
          .sum(:revenue)
      end

      def month_bucket_sql
        Arel.sql(<<~SQL.squish)
          FLOOR(EXTRACT(EPOCH FROM (conversions.converted_at - (
            SELECT MIN(c2.converted_at) FROM conversions c2
            WHERE c2.identity_id = conversions.identity_id
          ))) / #{SECONDS_PER_MONTH})::int
        SQL
      end
    end
  end
end
