module Dashboard
  class ConversionsDataService < ApplicationService
    CACHE_TTL = 5.minutes

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
        by_channel: by_channel,
        by_conversion_name: by_conversion_name,
        time_series: time_series,
        top_campaigns: top_campaigns
      }
    end

    def cache_key
      "dashboard/conversions/#{account.prefix_id}/#{params_hash}"
    end

    def params_hash
      Digest::MD5.hexdigest(cache_params.to_json)[0..11]
    end

    def cache_params
      {
        models: filter_params[:models].map(&:id).sort,
        date_range: filter_params[:date_range],
        channels: filter_params[:channels].sort,
        conversion_filters: conversion_filters,
        breakdown_dimension: breakdown_dimension,
        test_mode: test_mode
      }
    end

    def totals
      Queries::TotalsQuery.new(
        credits_scope,
        prior_scope: prior_credits_scope,
        sessions_scope: sessions_scope,
        prior_sessions_scope: prior_sessions_scope
      ).call
    end

    def by_channel
      Queries::ByChannelQuery.new(credits_scope).call
    end

    def time_series
      Queries::TimeSeriesQuery.new(credits_scope, date_range: date_range).call
    end

    def top_campaigns
      Queries::TopCampaignsQuery.new(credits_scope).call
    end

    def by_conversion_name
      Queries::ByConversionNameQuery.new(credits_scope, dimension: breakdown_dimension).call
    end

    def conversion_filters
      @conversion_filters ||= filter_params[:conversion_filters] || []
    end

    def breakdown_dimension
      @breakdown_dimension ||= filter_params[:breakdown_dimension] || "conversion_type"
    end

    def credits_scope
      @credits_scope ||= build_credits_scope(date_range)
    end

    def prior_credits_scope
      @prior_credits_scope ||= build_credits_scope(date_range.prior_period)
    end

    def sessions_scope
      @sessions_scope ||= build_sessions_scope(date_range)
    end

    def prior_sessions_scope
      @prior_sessions_scope ||= build_sessions_scope(date_range.prior_period)
    end

    def build_credits_scope(range)
      Scopes::FilteredCreditsScope.new(
        account: account,
        models: filter_params[:models],
        date_range: range,
        channels: filter_params[:channels],
        conversion_filters: conversion_filters,
        test_mode: test_mode
      ).call
    end

    def build_sessions_scope(range)
      Scopes::SessionsScope.new(
        account: account,
        date_range: range,
        channels: filter_params[:channels],
        test_mode: test_mode
      ).call
    end

    def test_mode
      @test_mode ||= filter_params[:test_mode] || false
    end

    def date_range
      @date_range ||= DateRangeParser.new(filter_params[:date_range])
    end
  end
end
