# frozen_string_literal: true

require "test_helper"

module Dashboard
  class ConversionsControllerTest < ActionDispatch::IntegrationTest
    setup do
      # Enable live mode so default view mode is production
      accounts(:one).update!(live_mode_enabled: true)
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
      assert_select ".grid.grid-cols-1.sm\\:grid-cols-2.lg\\:grid-cols-3 > *", count: 6
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

    # ==========================================
    # CLV Comparison Mode Tests
    # ==========================================

    test "clv mode renders single model view by default" do
      create_clv_test_data
      enable_clv_mode

      get dashboard_conversions_path(account_id: account.prefix_id)

      assert_response :success
      assert controller.instance_variable_get(:@clv_mode)
      assert_not controller.instance_variable_get(:@comparison_mode)
      assert_equal 1, controller.instance_variable_get(:@clv_results).length
    end

    test "clv mode renders comparison mode with two models" do
      create_clv_test_data
      enable_clv_mode
      first_touch = attribution_models(:first_touch)
      last_touch = attribution_models(:last_touch)

      get dashboard_conversions_path(
        account_id: account.prefix_id,
        models: [first_touch.prefix_id, last_touch.prefix_id]
      )

      assert_response :success
      assert controller.instance_variable_get(:@clv_mode)
      assert controller.instance_variable_get(:@comparison_mode)
      assert_equal 2, controller.instance_variable_get(:@clv_results).length
    end

    test "clv comparison results contain model and data" do
      create_clv_test_data
      enable_clv_mode
      first_touch = attribution_models(:first_touch)
      last_touch = attribution_models(:last_touch)

      get dashboard_conversions_path(
        account_id: account.prefix_id,
        models: [first_touch.prefix_id, last_touch.prefix_id]
      )

      clv_results = controller.instance_variable_get(:@clv_results)
      assert clv_results.first[:model].present?
      assert clv_results.first[:result][:success]
      assert clv_results.first[:result][:data].present?
    end

    test "clv comparison panels show model names" do
      create_clv_test_data
      enable_clv_mode
      first_touch = attribution_models(:first_touch)
      last_touch = attribution_models(:last_touch)

      get dashboard_conversions_path(
        account_id: account.prefix_id,
        models: [first_touch.prefix_id, last_touch.prefix_id]
      )

      assert_response :success
      assert_select "h3", text: first_touch.name.titleize
      assert_select "h3", text: last_touch.name.titleize
    end

    test "clv comparison panels have different border colors" do
      create_clv_test_data
      enable_clv_mode
      first_touch = attribution_models(:first_touch)
      last_touch = attribution_models(:last_touch)

      get dashboard_conversions_path(
        account_id: account.prefix_id,
        models: [first_touch.prefix_id, last_touch.prefix_id]
      )

      assert_response :success
      assert_select ".clv-panel.border-indigo-500", count: 1
      assert_select ".clv-panel.border-teal-500", count: 1
    end

    test "clv comparison mode uses side-by-side grid layout" do
      create_clv_test_data
      enable_clv_mode
      first_touch = attribution_models(:first_touch)
      last_touch = attribution_models(:last_touch)

      get dashboard_conversions_path(
        account_id: account.prefix_id,
        models: [first_touch.prefix_id, last_touch.prefix_id]
      )

      assert_response :success
      assert_select "[data-testid='clv-dashboard'] > .grid.grid-cols-1.sm\\:grid-cols-2"
    end

    test "clv single model view does not use comparison grid" do
      create_clv_test_data
      enable_clv_mode

      get dashboard_conversions_path(account_id: account.prefix_id)

      assert_response :success
      # Single model view should not have a direct child grid inside clv-dashboard
      assert_select "[data-testid='clv-dashboard'] > .grid.grid-cols-1.sm\\:grid-cols-2", count: 0
    end

    private

    def sign_in_as(user)
      post login_path, params: { email: user.email, password: "password123" }
    end

    def enable_clv_mode
      # Use account_id param to explicitly select account(:one)
      patch dashboard_clv_mode_path, params: { mode: "clv", account_id: account.prefix_id }
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
        converted_at: 5.days.ago,
        is_test: false
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
        converted_at: 5.days.ago,
        is_test: false
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
      # Create 3 sessions for the journey
      s1 = account.sessions.create!(
        visitor: visitors(:one),
        session_id: "sess_101",
        started_at: 10.days.ago,
        is_test: false
      )
      s2 = account.sessions.create!(
        visitor: visitors(:one),
        session_id: "sess_102",
        started_at: 7.days.ago,
        is_test: false
      )
      s3 = account.sessions.create!(
        visitor: visitors(:one),
        session_id: "sess_103",
        started_at: 5.days.ago,
        is_test: false
      )

      # Create conversion with 3 sessions in journey
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 5.days.ago,
        journey_session_ids: [s1.id, s2.id, s3.id],
        is_test: false
      )

      # Create credit (only 1 needed for first touch)
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: s1.id,
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        is_test: false
      )
    end

    def create_clv_test_data
      identity = account.identities.create!(
        external_id: "clv_test_customer",
        first_identified_at: 30.days.ago,
        last_identified_at: Time.current
      )

      # Create acquisition conversion
      acquisition = account.conversions.create!(
        visitor: visitors(:one),
        identity: identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 20.days.ago,
        is_test: false
      )

      # Create attribution credits for both models
      [first_touch_model, attribution_models(:last_touch)].each do |model|
        account.attribution_credits.create!(
          conversion: acquisition,
          attribution_model: model,
          session_id: rand(1000..9999),
          channel: Channels::ORGANIC_SEARCH,
          credit: 1.0,
          revenue_credit: 0,
          is_test: false
        )
      end

      # Create a payment
      payment = account.conversions.create!(
        visitor: visitors(:one),
        identity: identity,
        conversion_type: "payment",
        revenue: 100,
        converted_at: 10.days.ago,
        is_test: false
      )

      [first_touch_model, attribution_models(:last_touch)].each do |model|
        account.attribution_credits.create!(
          conversion: payment,
          attribution_model: model,
          session_id: rand(1000..9999),
          channel: Channels::ORGANIC_SEARCH,
          credit: 1.0,
          revenue_credit: 100,
          is_test: false
        )
      end
    end
  end
end
