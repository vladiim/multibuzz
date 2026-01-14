require "test_helper"

module Demo
  class DashboardControllerTest < ActionDispatch::IntegrationTest
    test "renders without authentication" do
      get demo_dashboard_path

      assert_response :success
    end

    test "displays demo badge" do
      get demo_dashboard_path

      assert_select ".bg-yellow-50"
      assert_match(/Sample Data/, response.body)
    end

    test "displays tab navigation" do
      get demo_dashboard_path

      assert_match(/Conversions/, response.body)
      assert_match(/Funnel/, response.body)
    end

    test "displays signup CTA" do
      get demo_dashboard_path

      assert_select "a[href='#{signup_path}']"
    end

    test "displays bottom CTA banner" do
      get demo_dashboard_path

      assert_match(/Ready to see your own data/, response.body)
    end

    test "defaults to transactions mode" do
      get demo_dashboard_path

      assert_nil session[:demo_clv_mode]
    end
  end
end
