# frozen_string_literal: true

require "test_helper"

module Dashboard
  class ConversionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      # Complete onboarding so default view mode is production
      accounts(:one).update!(onboarding_progress: (1 << Account::Onboarding::ONBOARDING_STEPS.size) - 1)
      sign_in_as users(:one)
      AttributionCredit.delete_all
      Conversion.where(account: account).delete_all
    end

    test "renders single model view by default" do
      get dashboard_conversions_path

      assert_response :success
      assert_not controller.instance_variable_get(:@comparison_mode)
    end

    test "renders comparison mode with two models" do
      first_touch = attribution_models(:first_touch)
      last_touch = attribution_models(:last_touch)

      get dashboard_conversions_path(models: [first_touch.prefix_id, last_touch.prefix_id])

      assert_response :success
      assert controller.instance_variable_get(:@comparison_mode)
      assert_equal 2, controller.instance_variable_get(:@results).length
    end

    test "returns totals with new journey metrics" do
      create_test_credits

      get dashboard_conversions_path

      assert_response :success
      result = controller.instance_variable_get(:@results).first[:result]
      totals = result[:data][:totals]

      assert totals.key?(:conversions)
      assert totals.key?(:revenue)
      assert totals.key?(:aov)
      assert totals.key?(:avg_days_to_convert)
      assert totals.key?(:avg_channels_to_convert)
      assert totals.key?(:avg_visits_to_convert)
    end

    test "calculates avg_channels_to_convert correctly" do
      create_multi_channel_conversion

      get dashboard_conversions_path

      assert_response :success
      result = controller.instance_variable_get(:@results).first[:result]
      totals = result[:data][:totals]

      assert_equal 2.0, totals[:avg_channels_to_convert]
    end

    test "calculates avg_visits_to_convert correctly" do
      create_multi_visit_conversion

      get dashboard_conversions_path

      assert_response :success
      result = controller.instance_variable_get(:@results).first[:result]
      totals = result[:data][:totals]

      assert_equal 3.0, totals[:avg_visits_to_convert]
    end

    test "comparison results include panel_index for color theming" do
      first_touch = attribution_models(:first_touch)
      last_touch = attribution_models(:last_touch)

      get dashboard_conversions_path(models: [first_touch.prefix_id, last_touch.prefix_id])

      assert_response :success
      assert_select ".dashboard-panel.border-indigo-500", count: 1
      assert_select ".dashboard-panel.border-teal-500", count: 1
    end

    test "single model view renders 6 KPI cards" do
      get dashboard_conversions_path

      assert_response :success
      # Should have 6 KPIs: conversions, revenue, aov, avg_days, avg_channels, avg_visits
      assert_select ".grid.grid-cols-2.lg\\:grid-cols-3 > *", count: 6
    end

    # ==========================================
    # Metric selection tests
    # ==========================================

    test "avg_channels metric is selectable via URL param" do
      get dashboard_conversions_path(metric: "avg_channels")

      assert_response :success
      assert_equal "avg_channels", controller.instance_variable_get(:@filter_params)[:metric]
    end

    test "avg_visits metric is selectable via URL param" do
      get dashboard_conversions_path(metric: "avg_visits")

      assert_response :success
      assert_equal "avg_visits", controller.instance_variable_get(:@filter_params)[:metric]
    end

    test "avg_days metric is selectable via URL param" do
      get dashboard_conversions_path(metric: "avg_days")

      assert_response :success
      assert_equal "avg_days", controller.instance_variable_get(:@filter_params)[:metric]
    end

    test "avg_channels KPI card has link to select metric" do
      get dashboard_conversions_path

      assert_response :success
      assert_select "a[href*='metric=avg_channels']"
    end

    test "avg_visits KPI card has link to select metric" do
      get dashboard_conversions_path

      assert_response :success
      assert_select "a[href*='metric=avg_visits']"
    end

    test "avg_days KPI card has link to select metric" do
      get dashboard_conversions_path

      assert_response :success
      assert_select "a[href*='metric=avg_days']"
    end

    test "selected avg_channels metric shows ring highlight" do
      get dashboard_conversions_path(metric: "avg_channels")

      assert_response :success
      assert_select "a.ring-2.ring-indigo-500[href*='metric=avg_channels']"
    end

    test "chart title updates for avg_channels metric" do
      get dashboard_conversions_path(metric: "avg_channels")

      assert_response :success
      assert_select "h3", text: "Avg Channels by Channel"
    end

    test "chart title updates for avg_visits metric" do
      get dashboard_conversions_path(metric: "avg_visits")

      assert_response :success
      assert_select "h3", text: "Avg Visits by Channel"
    end

    private

    def sign_in_as(user)
      post login_path, params: { email: user.email, password: "password123" }
    end

    def account
      @account ||= accounts(:one)
    end

    def first_touch_model
      @first_touch_model ||= attribution_models(:first_touch)
    end

    def create_test_credits
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        revenue: 100,
        converted_at: 5.days.ago
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 1,
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        revenue_credit: 100,
        is_test: false
      )
    end

    def create_multi_channel_conversion
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 5.days.ago
      )

      # 2 different channels for this conversion
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 1,
        channel: Channels::PAID_SEARCH,
        credit: 0.5,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 2,
        channel: Channels::EMAIL,
        credit: 0.5,
        is_test: false
      )
    end

    def create_multi_visit_conversion
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 5.days.ago
      )

      # 3 visits for this conversion
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 101,
        channel: Channels::PAID_SEARCH,
        credit: 0.33,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 102,
        channel: Channels::PAID_SEARCH,
        credit: 0.33,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 103,
        channel: Channels::PAID_SEARCH,
        credit: 0.34,
        is_test: false
      )
    end
  end
end
