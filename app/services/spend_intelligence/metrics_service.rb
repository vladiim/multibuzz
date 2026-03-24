# frozen_string_literal: true

module SpendIntelligence
  class MetricsService < ApplicationService
    CACHE_TTL = 5.minutes
    MICRO_UNIT = AdSpendRecord::MICRO_UNIT

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
      {
        totals: totals,
        by_channel: channel_metrics.call,
        time_series: breakdowns.time_series,
        by_device: breakdowns.by_device,
        by_hour: breakdowns.by_hour,
        payback: payback_data,
        recommendations: recommendations
      }
    end

    def totals
      {
        blended_roas: channel_metrics.blended_roas,
        total_spend_micros: channel_metrics.total_spend_micros,
        total_spend: spend_in_units(channel_metrics.total_spend_micros),
        attributed_revenue: channel_metrics.total_revenue,
        currency: primary_currency,
        ncac: ncac,
        mer: mer
      }
    end

    # --- Delegated Queries ---

    def breakdowns
      @breakdowns ||= Queries::BreakdownsQuery.new(spend_scope: spend_scope, credits_scope: credits_scope)
    end

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

    def mer
      @mer ||= total_business_revenue
        &.then { |rev| rev / spend_in_units(channel_metrics.total_spend_micros) }
        &.then { |ratio| ratio.round(2) }
    end

    def total_business_revenue
      @total_business_revenue ||= account.conversions
        .where(converted_at: date_range)
        .then { |scope| test_mode ? scope.test_data : scope.production }
        .sum(:revenue).to_f
        .then { |rev| rev.positive? && channel_metrics.total_spend_micros.positive? ? rev : nil }
    end

    def primary_attribution_model
      @primary_attribution_model ||= attribution_models.first
    end

    # --- Response Curves & Recommendations ---

    def response_curves
      @response_curves ||= ResponseCurveService.new(
        spend_scope: spend_scope,
        credits_scope: credits_scope
      ).call
    end

    def recommendations
      @recommendations ||= channel_metrics.call
        .select { |row| fittable_curve?(row[:channel]) }
        .map(&method(:build_recommendation))
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

    def channel_metrics
      @channel_metrics ||= Queries::ChannelMetricsQuery.new(
        spend_scope: spend_scope,
        credits_scope: credits_scope
      )
    end

    def spend_scope
      @spend_scope ||= Scopes::SpendScope.new(
        account: account,
        date_range: date_range,
        channels: channels,
        test_mode: test_mode
      ).call
    end

    def credits_scope
      @credits_scope ||= Dashboard::Scopes::CreditsScope.new(
        account: account,
        models: attribution_models,
        date_range: date_range_parser,
        channels: channels,
        test_mode: test_mode
      ).call
    end

    def spend_in_units(micros) = (micros.to_d / MICRO_UNIT).round(2)
    def primary_currency = account.ad_platform_connections.active_connections.first&.currency
    def date_range = date_range_parser.start_date..date_range_parser.end_date
    def date_range_parser = @date_range_parser ||= Dashboard::DateRangeParser.new(filter_params[:date_range])
    def channels = @channels ||= filter_params[:channels] || Channels::ALL
    def attribution_models = @attribution_models ||= filter_params[:models] || account.attribution_models.active
    def test_mode = @test_mode ||= filter_params[:test_mode] || false
    def cache_key = "spend_intelligence/#{account.prefix_id}/#{params_hash}"
    def params_hash = Digest::MD5.hexdigest(cache_params.to_json)[0..11]

    def cache_params
      {
        date_range: filter_params[:date_range],
        channels: channels.sort,
        models: attribution_models.map(&:id).sort,
        test_mode: test_mode
      }
    end
  end
end
