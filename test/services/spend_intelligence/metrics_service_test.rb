# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  class MetricsServiceTest < ActiveSupport::TestCase
    REVENUE = 99.99

    setup do
      account.attribution_credits.delete_all
      account.conversions.delete_all
      create_credit(channel: Channels::PAID_SEARCH, revenue_credit: REVENUE)
    end

    test "returns success with data" do
      result = service.call

      assert result[:success]
      assert_predicate result[:data], :present?
    end

    test "returns totals with blended ROAS" do
      totals = service.call[:data][:totals]

      assert_kind_of Numeric, totals[:blended_roas]
      assert_predicate totals[:blended_roas], :positive?
    end

    test "returns total spend in micros and units" do
      totals = service.call[:data][:totals]

      assert_predicate totals[:total_spend_micros], :positive?
      assert_equal (totals[:total_spend_micros].to_d / AdSpendRecord::MICRO_UNIT).round(2), totals[:total_spend]
    end

    test "returns attributed revenue" do
      totals = service.call[:data][:totals]

      assert_equal REVENUE, totals[:attributed_revenue]
    end

    test "returns by_channel breakdown" do
      by_channel = service.call[:data][:by_channel]

      assert_kind_of Array, by_channel
      assert by_channel.any? { |r| r[:channel] == Channels::PAID_SEARCH }
    end

    test "caches results" do
      first = service.call
      second = service.call

      assert_equal first[:data], second[:data]
    end

    test "returns time_series with daily spend and ROAS" do
      data = service.call[:data][:time_series]

      assert_kind_of Array, data
      assert_predicate data, :present?
      assert_equal %i[date spend_micros spend revenue roas].sort, data.first.keys.sort
    end

    test "returns by_device breakdown" do
      data = service.call[:data][:by_device]

      assert_kind_of Array, data
      assert_predicate data, :present?
      assert_equal %i[device spend_micros impressions clicks cpc_micros].sort, data.first.keys.sort
    end

    test "returns by_hour breakdown" do
      data = service.call[:data][:by_hour]

      assert_kind_of Array, data
      assert_predicate data, :present?
      assert_equal %i[hour spend_micros].sort, data.first.keys.sort
    end

    test "by_device sorts by spend descending" do
      data = service.call[:data][:by_device]
      spends = data.map { |d| d[:spend_micros] }

      assert_equal spends.sort.reverse, spends
    end

    test "scopes to account" do
      other_service = MetricsService.new(accounts(:two), filter_params)
      result = other_service.call

      assert result[:success]
      assert_not_equal service.call[:data][:totals][:total_spend_micros],
                       result[:data][:totals][:total_spend_micros]
    end

    test "compare key is nil when only one model is selected" do
      data = service.call[:data]

      assert_nil data[:compare]
    end

    test "compare contains per-model totals when two models are selected" do
      first_touch_credit = 42.0
      create_credit_for(model: first_touch_model, channel: Channels::DIRECT, revenue_credit: first_touch_credit)

      data = MetricsService.new(account, filter_params.merge(models: [ attribution_model, first_touch_model ])).call[:data]

      assert_equal REVENUE, data[:totals][:attributed_revenue]
      assert_equal first_touch_credit, data[:compare][:totals][:attributed_revenue]
    end

    test "compare totals reflect the second model only, not blended" do
      create_credit_for(model: first_touch_model, channel: Channels::PAID_SEARCH, revenue_credit: 17.0)

      data = MetricsService.new(account, filter_params.merge(models: [ attribution_model, first_touch_model ])).call[:data]

      assert_in_delta REVENUE, data[:totals][:attributed_revenue], 0.001,
        "primary must reflect last_touch only (not summed across models)"
      assert_in_delta 17.0, data[:compare][:totals][:attributed_revenue], 0.001,
        "compare must reflect first_touch only"
    end

    test "totals carry platform_revenue, gap, and gap_pct" do
      totals = service.call[:data][:totals]

      assert_predicate totals[:platform_revenue], :positive?
      assert_in_delta(totals[:attributed_revenue] - totals[:platform_revenue], totals[:gap], 0.01)
      assert_kind_of Numeric, totals[:gap_pct]
    end

    test "by_channel rows carry platform_revenue, gap, and gap_pct" do
      paid_search = service.call[:data][:by_channel].find { |r| r[:channel] == Channels::PAID_SEARCH }

      assert_kind_of Numeric, paid_search[:platform_revenue]
      assert_kind_of Numeric, paid_search[:gap]
      assert_in_delta(paid_search[:attributed_revenue] - paid_search[:platform_revenue], paid_search[:gap], 0.01)
    end

    test "compare data does not include gap fields" do
      data = MetricsService.new(account, filter_params.merge(models: [ attribution_model, first_touch_model ])).call[:data]

      refute_includes data[:compare][:totals].keys, :gap
      refute_includes data[:compare][:by_channel].first.keys, :gap
    end

    test "by_channel rows carry confidence band data when multiple models are active" do
      create_credit_for(model: first_touch_model, channel: Channels::PAID_SEARCH, revenue_credit: 50.0)

      paid_search = service.call[:data][:by_channel].find { |r| r[:channel] == Channels::PAID_SEARCH }

      assert_kind_of Hash, paid_search[:confidence_band]
      assert_kind_of Numeric, paid_search[:confidence_band][:min]
      assert_kind_of Numeric, paid_search[:confidence_band][:max]
    end

    test "totals carry a prior_period delta hash with range_days and percentage deltas" do
      prior_revenue = 50.0
      account.attribution_credits.create!(
        conversion: account.conversions.create!(
          visitor: visitors(:one), conversion_type: "purchase", revenue: prior_revenue, converted_at: 45.days.ago
        ),
        session_id: 1, attribution_model: attribution_model, channel: Channels::PAID_SEARCH,
        credit: 1.0, revenue_credit: prior_revenue, is_test: false
      )

      prior_period = service.call[:data][:totals][:prior_period]

      assert_kind_of Hash, prior_period
      assert_equal 30, prior_period[:range_days]
      assert_kind_of Numeric, prior_period[:attributed_revenue_pct]
    end

    test "prior_period deltas are nil when prior period had no spend or revenue" do
      account.ad_spend_records.where("spend_date < ?", 30.days.ago).destroy_all

      prior_period = service.call[:data][:totals][:prior_period]

      assert_nil prior_period[:total_spend_pct]
      assert_nil prior_period[:attributed_revenue_pct]
    end

    test "confidence band is nil when only one model is active" do
      account.attribution_models.where.not(id: attribution_model.id).update_all(is_active: false)

      paid_search = service.call[:data][:by_channel].find { |r| r[:channel] == Channels::PAID_SEARCH }

      assert_nil paid_search[:confidence_band]
    end

    private

    def service
      @service ||= MetricsService.new(account, filter_params)
    end

    def filter_params
      { date_range: "30d", models: [ attribution_model ] }
    end

    def create_credit(channel:, revenue_credit:)
      create_credit_for(model: attribution_model, channel: channel, revenue_credit: revenue_credit)
    end

    def create_credit_for(model:, channel:, revenue_credit:)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        revenue: revenue_credit,
        converted_at: 1.day.ago
      )
      account.attribution_credits.create!(
        conversion: conversion,
        session_id: 1,
        attribution_model: model,
        channel: channel,
        credit: 1.0,
        revenue_credit: revenue_credit,
        is_test: false
      )
    end

    def account = @account ||= accounts(:one)
    def attribution_model = @attribution_model ||= attribution_models(:last_touch)
    def first_touch_model = @first_touch_model ||= attribution_models(:first_touch)
  end
end
