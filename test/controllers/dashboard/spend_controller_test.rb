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

    private

    def account
      @account ||= accounts(:one)
    end
  end
end
