# frozen_string_literal: true

require "test_helper"

module Attribution
  class CalculatorTest < ActiveSupport::TestCase
    test "should calculate credits using specified attribution model" do
      session_one
      session_two

      credits = service.call

      assert_equal 2, credits.size
      assert_equal "organic_search", credits[0][:channel]
      assert_equal "email", credits[1][:channel]
    end

    test "should use algorithm from attribution model" do
      session_one
      session_two

      first_touch_service = build_service(model: first_touch_model)
      credits = first_touch_service.call

      assert_equal 1, credits.size
      assert_equal 1.0, credits[0][:credit]
      assert_equal session_one.id, credits[0][:session_id]
    end

    test "should enrich credits with UTM data from sessions" do
      session_one
      session_two

      credits = service.call

      assert_equal "google", credits[0][:utm_source]
      assert_equal "organic", credits[0][:utm_medium]
      assert_nil credits[0][:utm_campaign]

      assert_equal "newsletter", credits[1][:utm_source]
      assert_equal "email", credits[1][:utm_medium]
      assert_equal "weekly", credits[1][:utm_campaign]
    end

    test "should calculate revenue credits when conversion has revenue" do
      session_one
      session_two

      conversion_with_revenue = build_conversion(revenue: 100.00)
      revenue_service = build_service(conversion: conversion_with_revenue)

      credits = revenue_service.call

      assert_equal 2, credits.size
      credits.each do |credit|
        assert_not_nil credit[:revenue_credit]
        assert_in_delta 50.0, credit[:revenue_credit], 0.01
      end
    end

    test "should handle conversion without revenue" do
      session_one
      session_two

      credits = service.call

      assert_equal 2, credits.size
      credits.each do |credit|
        assert_nil credit[:revenue_credit]
      end
    end

    test "should use model lookback window" do
      custom_model = build_model(lookback_days: 7)
      old_session = build_session(days_ago: 10, channel: "paid_search")
      recent_session = build_session(days_ago: 5, channel: "display")

      custom_service = build_service(model: custom_model)
      credits = custom_service.call

      session_ids = credits.map { |c| c[:session_id] }
      assert_includes session_ids, recent_session.id
      assert_not_includes session_ids, old_session.id
    end

    test "should validate credits sum to 1.0" do
      session_one
      session_two

      credits = service.call

      total = credits.sum { |c| c[:credit] }
      assert_in_delta 1.0, total, 0.0001
    end

    test "should return empty array for visitor with no sessions" do
      empty_visitor = visitors(:other_account_visitor)
      empty_conversion = build_conversion(visitor: empty_visitor)
      empty_service = build_service(conversion: empty_conversion)

      credits = empty_service.call

      assert_empty credits
    end

    private

    def service
      @service ||= build_service
    end

    def build_service(conversion: default_conversion, model: linear_model)
      Attribution::Calculator.new(
        conversion: conversion,
        attribution_model: model
      )
    end

    def default_conversion
      @default_conversion ||= build_conversion
    end

    def build_conversion(visitor: default_visitor, revenue: nil)
      Conversion.create!(
        account: visitor.account,
        visitor: visitor,
        session_id: 1,
        event_id: 1,
        conversion_type: "purchase",
        revenue: revenue,
        converted_at: Time.current,
        journey_session_ids: []
      )
    end

    def linear_model
      @linear_model ||= attribution_models(:linear)
    end

    def first_touch_model
      @first_touch_model ||= attribution_models(:first_touch)
    end

    def build_model(lookback_days:)
      AttributionModel.create!(
        account: accounts(:two),
        name: "Custom #{lookback_days}d",
        model_type: :preset,
        algorithm: :linear,
        lookback_days: lookback_days,
        is_active: true
      )
    end

    def session_one
      @session_one ||= build_session(
        days_ago: 10,
        channel: "organic_search",
        utm_source: "google",
        utm_medium: "organic"
      )
    end

    def session_two
      @session_two ||= build_session(
        days_ago: 3,
        channel: "email",
        utm_source: "newsletter",
        utm_medium: "email",
        utm_campaign: "weekly"
      )
    end

    def build_session(days_ago:, channel:, utm_source: nil, utm_medium: nil, utm_campaign: nil)
      utm_data = {}
      utm_data["utm_source"] = utm_source if utm_source
      utm_data["utm_medium"] = utm_medium if utm_medium
      utm_data["utm_campaign"] = utm_campaign if utm_campaign

      Session.create!(
        account: default_visitor.account,
        visitor: default_visitor,
        session_id: SecureRandom.hex(16),
        started_at: days_ago.days.ago,
        channel: channel,
        initial_utm: utm_data
      )
    end

    def default_visitor
      @default_visitor ||= visitors(:two)
    end
  end
end
