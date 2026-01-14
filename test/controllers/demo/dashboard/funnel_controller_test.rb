require "test_helper"

module Demo
  module Dashboard
    class FunnelControllerTest < ActionDispatch::IntegrationTest
      test "renders without authentication" do
        get demo_dashboard_funnel_path

        assert_response :success
      end

      test "returns turbo frame content" do
        get demo_dashboard_funnel_path

        assert_select "turbo-frame#demo_funnel"
      end

      test "displays funnel stages" do
        get demo_dashboard_funnel_path

        assert_match(/Visits/, response.body)
        assert_match(/Purchase/, response.body)
      end

      test "displays dummy funnel data" do
        get demo_dashboard_funnel_path

        assert_match(/349,402/, response.body)
      end
    end
  end
end
