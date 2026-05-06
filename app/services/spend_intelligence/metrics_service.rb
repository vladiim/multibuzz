# frozen_string_literal: true

module SpendIntelligence
  class MetricsService < ApplicationService # rubocop:disable Metrics/ClassLength
    CACHE_TTL = 5.minutes
    MICRO_UNIT = AdSpendRecord::MICRO_UNIT

    # Range-length thresholds that pick the default timeseries granularity.
    # Sorted ascending; the first row whose `max_days` covers the selected range wins.
    # Anything beyond the last row falls through to the FALLBACK.
    RANGE_GRANULARITY_TABLE = [
      { max_days: 30,  granularity: :daily  },
      { max_days: 120, granularity: :weekly }
    ].freeze
    GRANULARITY_FALLBACK = :monthly

    def initialize(account, filter_params)
      @account = account
      @filter_params = filter_params
    end

    private

    attr_reader :account, :filter_params

    def run
      success_result(data: cached_data)
    end

    def cached_data
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { query_data }
    end

    def query_data
      primary_data.merge(compare: compare_data)
    end

    def primary_data
      {
        totals: primary_totals,
        by_channel: enriched_primary_by_channel,
        time_series: primary_breakdowns.time_series,
        by_device: primary_breakdowns.by_device,
        by_hour: primary_breakdowns.by_hour,
        payback: payback_data,
        recommendations: recommendations,
        confidence_band_active: confidence_band_query.present?
      }
    end

    def compare_data
      return nil unless compare_attribution_model

      {
        totals: base_totals_for(compare_metrics),
        by_channel: compare_metrics.call,
        time_series: compare_breakdowns.time_series
      }
    end

    def primary_totals
      base_totals_for(primary_metrics).merge(primary_platform_metrics.totals)
    end

    def base_totals_for(metrics)
      {
        blended_roas: metrics.blended_roas,
        total_spend_micros: metrics.total_spend_micros,
        total_spend: spend_in_units(metrics.total_spend_micros),
        attributed_revenue: metrics.total_revenue,
        currency: primary_currency,
        ncac: ncac,
        mer: mer_for(metrics)
      }
    end

    def enriched_primary_by_channel = primary_metrics.call.map(&method(:enrich_channel_row))

    def enrich_channel_row(row)
      row.merge(primary_platform_metrics.by_channel[row[:channel]] || {}, confidence_band: confidence_band_data[row[:channel]])
    end

    def confidence_band_data = @confidence_band_data ||= confidence_band_query&.by_channel || {}

    def confidence_band_query
      return nil unless active_attribution_models.size > 1

      @confidence_band_query ||= Queries::ConfidenceBandQuery.new(
        spend_scope: spend_scope,
        credits_scope_by_model: credits_scope_by_active_model,
        selected_model: primary_attribution_model
      )
    end

    def credits_scope_by_active_model
      @credits_scope_by_active_model ||= active_attribution_models.each_with_object({}) { |model, acc| acc[model] = credits_scope_for(model) }
    end

    def active_attribution_models = @active_attribution_models ||= account.attribution_models.active.to_a

    # --- Per-model query objects ---

    def primary_metrics = @primary_metrics ||= channel_metrics_for(primary_credits_scope)
    def compare_metrics = @compare_metrics ||= channel_metrics_for(compare_credits_scope)
    def primary_breakdowns = @primary_breakdowns ||= breakdowns_for(primary_credits_scope)
    def compare_breakdowns = @compare_breakdowns ||= breakdowns_for(compare_credits_scope)
    def primary_platform_metrics = @primary_platform_metrics ||= Queries::PlatformVsAttributedQuery.new(spend_scope: spend_scope, credits_scope: primary_credits_scope)

    def channel_metrics_for(credits_scope)
      Queries::ChannelMetricsQuery.new(spend_scope: spend_scope, credits_scope: credits_scope)
    end

    def breakdowns_for(credits_scope)
      Queries::BreakdownsQuery.new(
        spend_scope: spend_scope,
        credits_scope: credits_scope,
        timezone_offset: timezone_offset,
        timezone: report_timezone,
        accounting_mode: timeseries_accounting_mode,
        granularity: timeseries_granularity
      )
    end

    def primary_credits_scope = credits_scope_for(primary_attribution_model)
    def compare_credits_scope = credits_scope_for(compare_attribution_model)

    def credits_scope_for(model)
      Dashboard::Scopes::CreditsScope.new(
        account: account,
        models: [ model ].compact,
        date_range: date_range_parser,
        channels: channels,
        test_mode: test_mode
      ).call
    end

    def report_timezone
      @report_timezone ||= account.ad_platform_connections.active_connections.filter_map { |c| c.settings&.dig("timezone_name").presence }.first
    end

    # Accrual default: single-day ROAS reflects spend-day attribution, not conversion-day.
    def timeseries_accounting_mode
      mode = filter_params[:accounting_mode]&.to_sym
      Queries::BreakdownsQuery::ACCOUNTING_MODES.include?(mode) ? mode : :accrual
    end

    # URL override (?granularity=daily|weekly|monthly) wins; otherwise default by range length.
    def timeseries_granularity
      requested = filter_params[:granularity]&.to_sym
      Queries::BreakdownsQuery::GRANULARITIES.include?(requested) ? requested : default_granularity_for_range
    end

    def default_granularity_for_range
      RANGE_GRANULARITY_TABLE.find { |row| range_days <= row[:max_days] }&.dig(:granularity) || GRANULARITY_FALLBACK
    end

    def range_days
      @range_days ||= (date_range_parser.end_date - date_range_parser.start_date).to_i
    end

    # --- Payback, NCAC, MER ---

    def payback_data
      @payback_data ||= payback_query&.call || []
    end

    def payback_query
      primary_attribution_model&.then do |model|
        Queries::PaybackPeriodQuery.new(spend_scope: spend_scope, account: account, attribution_model: model, test_mode: test_mode)
      end
    end

    def ncac
      @ncac ||= payback_data
        .select { |row| row[:ncac] && row[:customers]&.positive? }
        .then { |rows| rows.empty? ? nil : (rows.sum { |r| r[:ncac] * r[:customers] } / rows.sum { |r| r[:customers] }).round(2) }
    end

    def mer_for(metrics)
      total_business_revenue
        &.then { |rev| rev / spend_in_units(metrics.total_spend_micros) }
        &.then { |ratio| ratio.round(2) }
    end

    def total_business_revenue
      @total_business_revenue ||= account.conversions
        .where(converted_at: date_range)
        .then { |scope| test_mode ? scope.test_data : scope.production }
        .sum(:revenue).to_f
        .then { |rev| rev.positive? && primary_metrics.total_spend_micros.positive? ? rev : nil }
    end

    def primary_attribution_model = @primary_attribution_model ||= attribution_models.first
    def compare_attribution_model = @compare_attribution_model ||= attribution_models[1]

    # --- Response Curves & Recommendations ---

    def response_curves
      @response_curves ||= ResponseCurveService.new(spend_scope: spend_scope, credits_scope: primary_credits_scope).call
    end

    def recommendations
      @recommendations ||= primary_metrics.call.select { |row| fittable_curve?(row[:channel]) }.map(&method(:build_recommendation))
    end

    def fittable_curve?(channel)
      response_curves.dig(channel, :k).present? && response_curves.dig(channel, :r_squared)&.positive?
    end

    def build_recommendation(row)
      RecommendationService.recommend(
        channel: row[:channel],
        roas: row[:roas] || 0,
        marginal_roas: response_curves.dig(row[:channel], :marginal_roas_at_current) || marginal_roas_for(row),
        current_spend: spend_in_units(row[:spend_micros])
      )
    end

    def marginal_roas_for(row)
      response_curves[row[:channel]]&.then do |curve|
        HillFunction.derivative(spend_in_units(row[:spend_micros]), curve[:k], curve[:s], curve[:ec50])
      end || 0
    end

    # --- Scopes & params ---

    def spend_scope
      @spend_scope ||= Scopes::SpendScope.new(account: account, date_range: date_range, channels: channels, test_mode: test_mode).call
    end

    def spend_in_units(micros) = (micros.to_d / MICRO_UNIT).round(2)
    def primary_currency = account.ad_platform_connections.active_connections.first&.currency
    def date_range = date_range_parser.start_date..date_range_parser.end_date
    def date_range_parser = @date_range_parser ||= Dashboard::DateRangeParser.new(filter_params[:date_range])
    def channels = @channels ||= filter_params[:channels] || Channels::ALL
    def attribution_models = @attribution_models ||= filter_params[:models] || account.attribution_models.active
    def test_mode = @test_mode ||= filter_params[:test_mode] || false
    def timezone_offset = @timezone_offset ||= filter_params[:timezone_offset]&.to_i
    def cache_key = "spend_intelligence/#{account.prefix_id}/#{params_hash}"
    def params_hash = Digest::MD5.hexdigest(cache_params.to_json)[0..11]

    def cache_params
      {
        date_range: filter_params[:date_range],
        channels: channels.sort,
        models: attribution_models.map(&:id).sort,
        test_mode: test_mode,
        accounting_mode: timeseries_accounting_mode,
        granularity: timeseries_granularity
      }
    end
  end
end
