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
        by_channel: channel_metrics.call
      }
    end

    def totals
      {
        blended_roas: channel_metrics.blended_roas,
        total_spend_micros: channel_metrics.total_spend_micros,
        total_spend: spend_in_units(channel_metrics.total_spend_micros),
        attributed_revenue: channel_metrics.total_revenue,
        currency: primary_currency
      }
    end

    # --- Queries ---

    def channel_metrics
      @channel_metrics ||= Queries::ChannelMetricsQuery.new(
        spend_scope: spend_scope,
        credits_scope: credits_scope
      )
    end

    # --- Scopes ---

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

    # --- Helpers ---

    def spend_in_units(micros)
      (micros.to_d / MICRO_UNIT).round(2)
    end

    def primary_currency
      account.ad_platform_connections.active_connections.first&.currency
    end

    # --- Filter extraction ---

    def date_range
      date_range_parser.start_date..date_range_parser.end_date
    end

    def date_range_parser
      @date_range_parser ||= Dashboard::DateRangeParser.new(filter_params[:date_range])
    end

    def channels
      @channels ||= filter_params[:channels] || Channels::ALL
    end

    def attribution_models
      @attribution_models ||= filter_params[:models] || account.attribution_models.active
    end

    def test_mode
      @test_mode ||= filter_params[:test_mode] || false
    end

    # --- Cache ---

    def cache_key
      "spend_intelligence/#{account.prefix_id}/#{params_hash}"
    end

    def params_hash
      Digest::MD5.hexdigest(cache_params.to_json)[0..11]
    end

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
