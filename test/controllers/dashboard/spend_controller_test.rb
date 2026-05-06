# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

module Dashboard
  class SpendControllerTest < ActionDispatch::IntegrationTest
    setup do
      accounts(:one).update!(live_mode_enabled: true)
      sign_in_as users(:one)
    end

    test "renders spend tab with connections" do
      get dashboard_spend_path

      assert_response :success
    end

    test "renders empty state without connections" do
      account.ad_platform_connections.update_all(status: :disconnected)

      get dashboard_spend_path

      assert_response :success
      assert_select "h3", text: "See where your money works hardest"
    end

    test "renders hero metrics" do
      get dashboard_spend_path

      assert_select "dt", text: "Blended ROAS"
      assert_select "dt", text: "Total Spend"
      assert_select "dt", text: "Attributed Revenue"
    end

    test "renders channel summary table" do
      get dashboard_spend_path

      assert_response :success
      assert_select "h3", text: "By Channel"
    end

    test "renders sub-tabs for overview and hourly/device" do
      get dashboard_spend_path

      assert_response :success
      assert_select "button", text: "Overview"
      assert_select "button", text: "Hourly / Device"
    end

    test "renders channel detail table" do
      get dashboard_spend_path

      assert_response :success
      assert_select "h4", text: "Channel Performance Detail"
    end

    test "scopes data to account" do
      get dashboard_spend_path

      assert_response :success

      result = controller.instance_variable_get(:@result)

      assert result[:success]
    end

    test "renders error state on service failure" do
      mock_service = Minitest::Mock.new
      mock_service.expect :call, { success: false, errors: [ "Test error" ] }

      SpendIntelligence::MetricsService.stub(:new, ->(_a, _f) { mock_service }) do
        get dashboard_spend_path
      end

      assert_response :success
      assert_select "p.text-red-700", /Test error/
      mock_service.verify
    end

    test "renders the attribution model selector with the active model name" do
      get dashboard_spend_path

      assert_select "[data-spend-model-selector]", count: 1
      assert_select "[data-spend-model-selector] [data-role='primary-label']",
        text: /first touch|last touch/i
    end

    test "models[] param drives the primary attribution model resolution" do
      get dashboard_spend_path, params: { models: [ attribution_models(:first_touch).prefix_id ] }

      assert_response :success
      filter = controller.instance_variable_get(:@filter_params)

      assert_equal [ attribution_models(:first_touch) ], filter[:models]
    end

    test "two models selected enable comparison mode in the service result" do
      get dashboard_spend_path, params: {
        models: [ attribution_models(:last_touch).prefix_id, attribution_models(:first_touch).prefix_id ]
      }

      assert_response :success
      data = controller.instance_variable_get(:@result)[:data]

      assert_not_nil data[:compare], "expected :compare data when two models are selected"
    end

    test "channel table renders delta columns when comparing two models" do
      get dashboard_spend_path, params: {
        models: [ attribution_models(:last_touch).prefix_id, attribution_models(:first_touch).prefix_id ]
      }

      assert_select "th", text: /Δ\s*ROAS/i
      assert_select "th", text: /Δ\s*Revenue/i
    end

    test "channel table omits delta columns when only one model is selected" do
      get dashboard_spend_path, params: { models: [ attribution_models(:last_touch).prefix_id ] }

      assert_select "th", text: /Δ\s*ROAS/i, count: 0
    end

    test "trend chart embeds compare time series JSON when comparing" do
      get dashboard_spend_path, params: {
        models: [ attribution_models(:last_touch).prefix_id, attribution_models(:first_touch).prefix_id ]
      }

      assert_select "#spend-trend-chart[data-chart-compare-data-value]"
      assert_select "#spend-trend-chart[data-chart-compare-name-value]"
    end

    private

    def account
      @account ||= accounts(:one)
    end
  end
end
