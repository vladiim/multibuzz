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

    test "scopes to account" do
      other_service = MetricsService.new(accounts(:two), filter_params)
      result = other_service.call

      assert result[:success]
      assert_not_equal service.call[:data][:totals][:total_spend_micros],
                       result[:data][:totals][:total_spend_micros]
    end

    private

    def service
      @service ||= MetricsService.new(account, filter_params)
    end

    def filter_params
      { date_range: "30d", models: [ attribution_model ] }
    end

    def create_credit(channel:, revenue_credit:)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        revenue: revenue_credit,
        converted_at: 1.day.ago
      )
      account.attribution_credits.create!(
        conversion: conversion,
        session_id: 1,
        attribution_model: attribution_model,
        channel: channel,
        credit: 1.0,
        revenue_credit: revenue_credit,
        is_test: false
      )
    end

    def account = @account ||= accounts(:one)
    def attribution_model = @attribution_model ||= attribution_models(:last_touch)
  end
end
