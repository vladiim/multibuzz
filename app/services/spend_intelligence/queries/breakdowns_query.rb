# frozen_string_literal: true

module SpendIntelligence
  module Queries
    class BreakdownsQuery
      MICRO_UNIT = AdSpendRecord::MICRO_UNIT

      ACCOUNTING_MODES = %i[cash accrual].freeze
      GRANULARITIES = %i[daily weekly monthly].freeze
      GRANULARITY_TRUNC_FIELD = { weekly: "week", monthly: "month" }.freeze

      def initialize(spend_scope:, credits_scope:, timezone_offset: nil, timezone: nil, accounting_mode: :cash, granularity: :daily) # rubocop:disable Metrics/ParameterLists
        raise ArgumentError, "unknown accounting_mode #{accounting_mode}" unless ACCOUNTING_MODES.include?(accounting_mode)
        raise ArgumentError, "unknown granularity #{granularity}" unless GRANULARITIES.include?(granularity)

        @spend_scope = spend_scope
        @credits_scope = credits_scope
        @timezone_offset = timezone_offset || 0
        @timezone = timezone
        @accounting_mode = accounting_mode
        @granularity = granularity
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

      attr_reader :spend_scope, :credits_scope, :timezone_offset, :timezone, :accounting_mode, :granularity

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
        @daily_spend ||= spend_scope.group(spend_date_group_expr).sum(:spend_micros)
      end

      def spend_date_group_expr
        trunc_field = GRANULARITY_TRUNC_FIELD[granularity]
        trunc_field ? Arel.sql("DATE_TRUNC('#{trunc_field}', spend_date)::date") : :spend_date
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
      #
      # LEFT JOIN + COALESCE: when an attribution_credit references a session
      # that no longer exists (archived, retention-dropped, or never persisted),
      # an INNER JOIN silently drops the row and the timeseries reads zero
      # while the hero correctly shows the full attributed revenue. Fall back
      # to the conversion timestamp so the daily total matches what the hero
      # and channel table report.
      def accrual_daily_revenue
        credits_scope
          .joins("LEFT JOIN sessions ON sessions.id = attribution_credits.session_id")
          .group(date_expr_for("COALESCE(sessions.started_at, conversions.converted_at)"))
          .sum(:revenue_credit)
      end

      # Stored timestamps are UTC values in `timestamp without time zone` columns.
      # Reinterpret as UTC, then shift to the report timezone, then extract the
      # truncated date for the chosen granularity (daily, weekly, monthly).
      def date_expr_for(column)
        shifted = timezone.blank? ? column : "(#{column} AT TIME ZONE 'UTC') AT TIME ZONE ?"
        truncated = truncate_expr(shifted)
        timezone.blank? ? Arel.sql(truncated) : Arel.sql(ActiveRecord::Base.sanitize_sql_array([ truncated, timezone ]))
      end

      def truncate_expr(shifted)
        trunc_field = GRANULARITY_TRUNC_FIELD[granularity]
        trunc_field ? "DATE_TRUNC('#{trunc_field}', #{shifted})::date" : "DATE(#{shifted})"
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
