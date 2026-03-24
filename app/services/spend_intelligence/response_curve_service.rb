# frozen_string_literal: true

module SpendIntelligence
  class ResponseCurveService
    MIN_WEEKS = 12

    def initialize(spend_scope:, credits_scope:)
      @spend_scope = spend_scope
      @credits_scope = credits_scope
    end

    def call
      weekly_data_by_channel
        .select { |_, weeks| weeks.size >= MIN_WEEKS }
        .transform_values { |weeks| HillFit.new(weeks).call }
    end

    def marginal_roas(channel, spend)
      call[channel]&.then { |curve| HillFunction.derivative(spend, curve[:k], curve[:s], curve[:ec50]) }
    end

    private

    attr_reader :spend_scope, :credits_scope

    def weekly_data_by_channel
      @weekly_data_by_channel ||= weekly_spend
        .each_with_object({}) { |((channel, week), micros), result| append_week(result, channel, week, micros) }
    end

    def append_week(result, channel, week, spend_micros)
      spend = spend_micros.to_f / AdSpendRecord::MICRO_UNIT
      return unless spend.positive?

      (result[channel] ||= []) << {
        week: week,
        spend: spend,
        revenue: weekly_revenue.fetch([ channel, week ], 0).to_f
      }
    end

    def weekly_spend
      @weekly_spend ||= spend_scope.group(:channel, week_sql).sum(:spend_micros)
    end

    def weekly_revenue
      @weekly_revenue ||= credits_scope.joins(:conversion)
        .group(:channel, Arel.sql("DATE_TRUNC('week', conversions.converted_at)::date"))
        .sum(:revenue_credit)
    end

    def week_sql = Arel.sql("DATE_TRUNC('week', spend_date)::date")
  end
end
