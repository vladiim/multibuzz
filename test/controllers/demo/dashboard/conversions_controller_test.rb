require "test_helper"

module Demo
  module Dashboard
    class ConversionsControllerTest < ActionDispatch::IntegrationTest
      test "renders without authentication" do
        get demo_dashboard_conversions_path

        assert_response :success
      end

      test "returns turbo frame content" do
        get demo_dashboard_conversions_path

        assert_select "turbo-frame#demo_conversions"
      end

      test "displays dummy conversion data" do
        get demo_dashboard_conversions_path

        assert_match(/2,382/, response.body)
      end

      test "renders transactions mode by default" do
        get demo_dashboard_conversions_path

        assert_select ".dashboard-section"
      end

      test "renders CLV mode when session set" do
        patch demo_dashboard_clv_mode_path, params: { mode: "clv" }
        get demo_dashboard_conversions_path

        assert_response :success
        assert_match(/Avg CLV|Customer LTV/, response.body)
      end
    end
  end
end
