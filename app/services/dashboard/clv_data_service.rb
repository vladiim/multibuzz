# frozen_string_literal: true

module Dashboard
  class ClvDataService < ApplicationService
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
        smiling_curve: smiling_curve,
        cohort_analysis: cohort_analysis,
        coverage: coverage,
        has_data: acquired_identity_ids.any?
      }
    end

    def cache_key
      "dashboard/clv/#{account.prefix_id}/#{params_hash}"
    end

    def params_hash
      Digest::MD5.hexdigest(cache_params.to_json)[0..11]
    end

    def cache_params
      {
        model_id: attribution_model&.id,
        date_range: filter_params[:date_range],
        channels: channels.is_a?(Array) ? channels.sort : channels,
        conversion_filters: conversion_filters,
        test_mode: test_mode
      }
    end

    def totals
      Queries::ClvTotalsQuery.new(
        account: account,
        identity_ids: acquired_identity_ids,
        test_mode: test_mode
      ).call
    end

    def by_channel
      Queries::ClvByChannelQuery.new(
        account: account,
        acquisition_conversions: acquisition_conversions,
        attribution_model: attribution_model,
        test_mode: test_mode
      ).call
    end

    def smiling_curve
      Queries::SmilingCurveQuery.new(
        account: account,
        acquisition_conversions: acquisition_conversions,
        attribution_model: attribution_model,
        test_mode: test_mode
      ).call
    end

    def cohort_analysis
      Queries::CohortAnalysisQuery.new(
        account: account,
        acquisition_conversions: acquisition_conversions,
        attribution_model: attribution_model,
        test_mode: test_mode
      ).call
    end

    def coverage
      total = conversions_in_range.count
      identified = conversions_in_range.where.not(identity_id: nil).count
      percentage = total.positive? ? (identified.to_f / total * 100).round(1) : 0

      { total: total, identified: identified, percentage: percentage }
    end

    def acquired_identity_ids
      @acquired_identity_ids ||= acquisition_conversions.pluck(:identity_id).compact
    end

    def acquisition_conversions
      @acquisition_conversions ||= Scopes::FilteredAcquisitionsScope.new(
        account: account,
        date_range: date_range,
        channels: channels,
        attribution_model: attribution_model,
        conversion_filters: conversion_filters,
        test_mode: test_mode
      ).call
    end

    def conversions_in_range
      @conversions_in_range ||= account.conversions
        .where(converted_at: date_range.to_range)
        .then { |scope| test_mode ? scope.test_data : scope.production }
    end

    def channels
      @channels ||= filter_params[:channels] || Channels::ALL
    end

    def conversion_filters
      @conversion_filters ||= filter_params[:conversion_filters] || []
    end

    def test_mode
      @test_mode ||= filter_params[:test_mode] || false
    end

    def date_range
      @date_range ||= DateRangeParser.new(filter_params[:date_range])
    end

    def attribution_model
      @attribution_model ||= filter_params[:models]&.first ||
        account.attribution_models.active.find_by(is_default: true) ||
        account.attribution_models.active.first
    end
  end
end
