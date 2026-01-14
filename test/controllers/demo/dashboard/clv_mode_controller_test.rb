require "test_helper"

module Demo
  module Dashboard
    class ClvModeControllerTest < ActionDispatch::IntegrationTest
      test "sets clv mode in session" do
        patch demo_dashboard_clv_mode_path, params: { mode: "clv" }

        assert_redirected_to demo_dashboard_path
        assert_equal "clv", session[:demo_clv_mode]
      end

      test "sets transactions mode in session" do
        patch demo_dashboard_clv_mode_path, params: { mode: "transactions" }

        assert_redirected_to demo_dashboard_path
        assert_equal "transactions", session[:demo_clv_mode]
      end

      test "defaults to transactions for invalid mode" do
        patch demo_dashboard_clv_mode_path, params: { mode: "invalid" }

        assert_redirected_to demo_dashboard_path
        assert_equal "transactions", session[:demo_clv_mode]
      end

      test "uses separate session key from authenticated dashboard" do
        patch demo_dashboard_clv_mode_path, params: { mode: "clv" }

        assert_equal "clv", session[:demo_clv_mode]
        assert_nil session[:clv_mode]
      end
    end
  end
end
