# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  module Queries
    class ConfidenceBandQueryTest < ActiveSupport::TestCase
      LAST_TOUCH_CREDIT = 80.0
      FIRST_TOUCH_CREDIT = 40.0

      setup do
        account.attribution_credits.delete_all
        account.conversions.delete_all
        create_credit(model: last_touch, channel: Channels::PAID_SEARCH, revenue_credit: LAST_TOUCH_CREDIT)
        create_credit(model: first_touch, channel: Channels::PAID_SEARCH, revenue_credit: FIRST_TOUCH_CREDIT)
      end

      test "returns min, max, and selected ROAS per channel across models" do
        band = query.by_channel[Channels::PAID_SEARCH]
        spend_units = paid_search_spend_micros / AdSpendRecord::MICRO_UNIT.to_f
        last_roas = (LAST_TOUCH_CREDIT / spend_units).round(2)
        first_roas = (FIRST_TOUCH_CREDIT / spend_units).round(2)

        assert_in_delta [ last_roas, first_roas ].min, band[:min], 0.01
        assert_in_delta [ last_roas, first_roas ].max, band[:max], 0.01
        assert_in_delta last_roas, band[:selected], 0.01
      end

      test "by_model carries the per-model ROAS keyed by model object" do
        by_model = query.by_channel[Channels::PAID_SEARCH][:by_model]

        assert_equal 2, by_model.size
        assert_includes by_model.keys.map(&:name), "Last Touch"
        assert_includes by_model.keys.map(&:name), "First Touch"
      end

      test "channel with no spend is omitted from results" do
        refute_includes query.by_channel.keys, Channels::EMAIL
      end

      test "channel with no credits in any model is omitted" do
        assert_nil query.by_channel[Channels::DISPLAY]
      end

      test "channel where only one model has credits collapses min == max == selected" do
        create_credit(model: last_touch, channel: Channels::DISPLAY, revenue_credit: 5.0)
        band = ConfidenceBandQuery.new(
          spend_scope: spend_scope,
          credits_scope_by_model: { last_touch => credits_scope_for(last_touch), first_touch => credits_scope_for(first_touch) },
          selected_model: last_touch
        ).by_channel[Channels::DISPLAY]
        roas = (5.0 / (display_spend_micros / AdSpendRecord::MICRO_UNIT.to_f)).round(2)

        assert_equal [ roas, roas, roas ], [ band[:min], band[:max], band[:selected] ]
      end

      test "selected is nil when the selected model is not in the credits map" do
        band = ConfidenceBandQuery.new(
          spend_scope: spend_scope,
          credits_scope_by_model: { first_touch => credits_scope_for(first_touch) },
          selected_model: last_touch
        ).by_channel[Channels::PAID_SEARCH]

        assert_nil band[:selected]
      end

      private

      def query
        @query ||= ConfidenceBandQuery.new(
          spend_scope: spend_scope,
          credits_scope_by_model: { last_touch => credits_scope_for(last_touch), first_touch => credits_scope_for(first_touch) },
          selected_model: last_touch
        )
      end

      def credits_scope_for(model)
        Dashboard::Scopes::CreditsScope.new(
          account: account,
          models: [ model ],
          date_range: date_range,
          test_mode: false
        ).call
      end

      def create_credit(model:, channel:, revenue_credit:)
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

      def paid_search_spend_micros
        ad_spend_records(:paid_search_today).spend_micros + ad_spend_records(:paid_search_yesterday).spend_micros
      end

      def display_spend_micros = ad_spend_records(:display_today).spend_micros

      def spend_scope
        @spend_scope ||= Scopes::SpendScope.new(account: account, date_range: Date.yesterday..Date.current).call
      end

      def account = @account ||= accounts(:one)
      def last_touch = @last_touch ||= attribution_models(:last_touch)
      def first_touch = @first_touch ||= attribution_models(:first_touch)
      def date_range = @date_range ||= Dashboard::DateRangeParser.new("30d")
    end
  end
end
