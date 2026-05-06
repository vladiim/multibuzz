# frozen_string_literal: true

module SpendIntelligence
  module Queries
    class BreakdownsQuery
      MICRO_UNIT = AdSpendRecord::MICRO_UNIT

      ACCOUNTING_MODES = %i[cash accrual].freeze

      def initialize(spend_scope:, credits_scope:, timezone_offset: nil, timezone: nil, accounting_mode: :cash) # rubocop:disable Metrics/ParameterLists
        raise ArgumentError, "unknown accounting_mode #{accounting_mode}" unless ACCOUNTING_MODES.include?(accounting_mode)

        @spend_scope = spend_scope
        @credits_scope = credits_scope
        @timezone_offset = timezone_offset || 0
        @timezone = timezone
        @accounting_mode = accounting_mode
      end

      def time_series
        all_dates.sort.map { |date| time_series_entry(date) }
      end

      def by_device
        device_aggregates
          .map { |row| device_entry(row) }
          .sort_by { |d| -(d[:spend_micros] || 0) }
      end

      def by_hour
        raw_hourly_spend
          .each_with_object(Hash.new(0)) { |(hour, spend), shifted| shifted[shift_hour(hour)] += spend }
          .sort_by(&:first)
          .map { |hour, spend| { hour: hour, spend_micros: spend } }
      end

      private

      attr_reader :spend_scope, :credits_scope, :timezone_offset, :timezone, :accounting_mode

      # --- Time Series ---

      def time_series_entry(date)
        spend = daily_spend[date] || 0
        revenue = (daily_revenue[date] || 0).to_f

        {
          date: date.to_s,
          spend_micros: spend,
          spend: spend_in_units(spend),
          revenue: revenue,
          roas: roas(spend, revenue)
        }
      end

      def daily_spend
        @daily_spend ||= spend_scope.group(:spend_date).sum(:spend_micros)
      end

      def all_dates
        daily_spend.keys | daily_revenue.keys
      end

      def daily_revenue
        @daily_revenue ||= accounting_mode == :accrual ? accrual_daily_revenue : cash_daily_revenue
      end

      # Cash: revenue dated by the conversion timestamp.
      # Hero KPIs use this; today's number is "what came in today."
      def cash_daily_revenue
        credits_scope.joins(:conversion)
          .group(date_expr_for("conversions.converted_at")).sum(:revenue_credit)
      end

      # Accrual: revenue dated by the touchpoint session that earned credit.
      # The timeseries uses this so single-day ROAS becomes "spend on day X
      # attributed back to revenue from spend on day X."
      def accrual_daily_revenue
        credits_scope
          .joins("INNER JOIN sessions ON sessions.id = attribution_credits.session_id")
          .group(date_expr_for("sessions.started_at")).sum(:revenue_credit)
      end

      def date_expr_for(column)
        return Arel.sql("DATE(#{column})") if timezone.blank?

        # Stored timestamps are UTC values in `timestamp without time zone`
        # columns. Reinterpret as UTC, then shift to the report timezone, then
        # extract the calendar date.
        Arel.sql(ActiveRecord::Base.sanitize_sql_array([
          "DATE((#{column} AT TIME ZONE 'UTC') AT TIME ZONE ?)",
          timezone
        ]))
      end

      # --- Device ---

      def device_aggregates
        spend_scope.group(:device)
          .select("device, SUM(spend_micros) AS total_spend, SUM(impressions) AS total_impressions, SUM(clicks) AS total_clicks")
      end

      def device_entry(row)
        {
          device: row.device,
          spend_micros: row.total_spend,
          impressions: row.total_impressions,
          clicks: row.total_clicks,
          cpc_micros: row.total_clicks.positive? ? row.total_spend / row.total_clicks : nil
        }
      end

      # --- Hourly ---

      def raw_hourly_spend
        @raw_hourly_spend ||= spend_scope.group(:spend_hour).sum(:spend_micros)
      end

      def shift_hour(hour) = (hour + timezone_offset) % 24

      # --- Helpers ---

      def roas(spend_micros, revenue)
        return nil unless spend_micros.positive?

        (revenue / spend_in_units(spend_micros)).round(2)
      end

      def spend_in_units(micros)
        micros.to_d / MICRO_UNIT
      end
    end
  end
end
