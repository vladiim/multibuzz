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

    test "channel table renders Platform Rev, Attributed Rev, and Gap columns" do
      get dashboard_spend_path

      assert_select "th", text: /Platform Rev/i
      assert_select "th", text: /Attributed Rev/i
      assert_select "th", text: /Gap %/i
    end

    test "hero strip includes Platform vs Attributed tile and not the MER tile" do
      get dashboard_spend_path

      assert_select "dt", text: /Platform vs Attributed/i
      assert_select "dt", text: "MER", count: 0
    end

    test "granularity URL param is honored by the metrics service via filter_params" do
      get dashboard_spend_path, params: { granularity: "weekly" }

      assert_response :success
      assert_select ".bg-white.shadow-sm", text: "W"
    end

    test "trend chart renders granularity and accounting mode pills" do
      get dashboard_spend_path

      assert_select "span", text: /Granularity/i
      assert_select "span", text: /Mode/i
      [ "D", "W", "M", "Cash", "Accrual" ].each do |label|
        assert_select "a", text: label
      end
    end

    test "channel table renders Confidence column when the account has multiple active models" do
      get dashboard_spend_path

      assert_select "th", text: /Confidence/i
    end

    test "channel table hides Confidence column when only one model is active" do
      attribution_models(:first_touch).update!(is_active: false)

      get dashboard_spend_path

      assert_select "th", text: /Confidence/i, count: 0
    end

    test "Attributed Revenue hero tile carries an MER sub-line when MER is computable" do
      account.conversions.create!(
        visitor: visitors(:one), conversion_type: "purchase", revenue: 500.0,
        converted_at: 1.day.ago, session_id: 1, event_id: 1, journey_session_ids: [ 1 ]
      )

      get dashboard_spend_path

      assert_select "dt", text: "Attributed Revenue"
      assert_select "[data-test-id='hero-attributed-revenue-mer']"
    end

    test "spend dashboard does not regress into a query explosion" do
      query_count = count_queries { get dashboard_spend_path }

      assert_operator query_count, :<, 50, "dashboard render should stay well under 50 queries"
    end

    private

    def count_queries
      count = 0
      counter = ->(_n, _s, _f, _id, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:name] == "TRANSACTION" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end


    def account
      @account ||= accounts(:one)
    end
  end
end
