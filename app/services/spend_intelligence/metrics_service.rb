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
        time_series: time_series,
        by_device: by_device,
        by_hour: by_hour
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

    # --- Time Series ---

    def time_series
      daily_spend = spend_scope.group(:spend_date).sum(:spend_micros)

      daily_spend.keys.sort.map do |date|
        spend = daily_spend[date] || 0
        revenue = (daily_revenue[date] || 0).to_f
        {
          date: date.to_s,
          spend_micros: spend,
          spend: spend_in_units(spend),
          revenue: revenue,
          roas: spend.positive? ? (revenue / spend_in_units(spend)).round(2) : nil
        }
      end
    end

    def daily_revenue
      @daily_revenue ||= credits_scope.joins(:conversion)
        .group(Arel.sql("DATE(conversions.converted_at)")).sum(:revenue_credit)
    end

    # --- Device & Hour Breakdowns ---

    def by_device
      spend_scope.group(:device)
        .select("device, SUM(spend_micros) AS total_spend, SUM(impressions) AS total_impressions, SUM(clicks) AS total_clicks")
        .map do |row|
          {
            device: row.device,
            spend_micros: row.total_spend,
            impressions: row.total_impressions,
            clicks: row.total_clicks,
            cpc_micros: row.total_clicks.positive? ? row.total_spend / row.total_clicks : nil
          }
        end
        .sort_by { |d| -(d[:spend_micros] || 0) }
    end

    def by_hour
      spend_scope.group(:spend_hour).sum(:spend_micros)
        .sort_by(&:first)
        .map { |hour, spend| { hour: hour, spend_micros: spend } }
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
