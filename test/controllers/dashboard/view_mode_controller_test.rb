# frozen_string_literal: true

require "test_helper"

module Dashboard
  class ViewModeControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as(user)
      # Explicitly set production mode in session for most tests
      patch dashboard_view_mode_path, params: { mode: "production" }
      follow_redirect!
    end

    test "should update view mode to test" do
      patch dashboard_view_mode_path, params: { mode: "test" }

      assert_redirected_to dashboard_path
      follow_redirect!
      assert_equal "test", session[:view_mode]
    end

    test "should update view mode to production" do
      # First set to test mode
      patch dashboard_view_mode_path, params: { mode: "test" }
      follow_redirect!

      # Then switch to production
      patch dashboard_view_mode_path, params: { mode: "production" }

      assert_redirected_to dashboard_path
      follow_redirect!
      assert_equal "production", session[:view_mode]
    end

    test "should reject invalid view mode" do
      patch dashboard_view_mode_path, params: { mode: "invalid" }

      assert_redirected_to dashboard_path
      follow_redirect!
      assert_equal "production", session[:view_mode]
    end

    test "should default to production when mode is blank" do
      patch dashboard_view_mode_path, params: { mode: "" }

      assert_redirected_to dashboard_path
      follow_redirect!
      assert_equal "production", session[:view_mode]
    end

    test "should require login" do
      logout

      patch dashboard_view_mode_path, params: { mode: "test" }

      assert_redirected_to login_path
    end

    # Note: Test/Live toggle moved from nav bar to account settings.
    # See AccountControllerTest for toggle tests.

    test "shows test mode banner when in test mode" do
      patch dashboard_view_mode_path, params: { mode: "test" }
      follow_redirect!

      assert_select "[data-testid='test-mode-banner']" do
        assert_select ".bg-amber-50"
      end
    end

    test "does not show test mode banner when in production mode" do
      get dashboard_path

      assert_select "[data-testid='test-mode-banner']", count: 0
    end

    test "defaults to test mode when live_mode_enabled is false" do
      single_account_user = users(:three)
      target_account = accounts(:one)

      reset!
      target_account.update!(live_mode_enabled: false)

      sign_in_as(single_account_user)
      get dashboard_path

      assert_response :success
      assert_nil session[:view_mode], "Session should not have view_mode set"
      assert_select "[data-testid='test-mode-banner']"
    end

    test "defaults to production mode when live_mode_enabled is true" do
      single_account_user = users(:three)
      target_account = accounts(:one)

      reset!
      target_account.update!(live_mode_enabled: true)

      sign_in_as(single_account_user)
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='test-mode-banner']", count: 0
    end

    test "switching to production mode enables live_mode on account" do
      current_account.update!(live_mode_enabled: false)

      patch dashboard_view_mode_path, params: { mode: "production" }

      assert current_account.reload.live_mode_enabled?,
        "live_mode_enabled should be true after switching to production"
    end

    test "switching to test mode disables live_mode on account" do
      current_account.update!(live_mode_enabled: true)

      patch dashboard_view_mode_path, params: { mode: "test" }

      assert_not current_account.reload.live_mode_enabled?,
        "live_mode_enabled should be false after switching to test"
    end

    test "user can still switch to production mode even when live_mode is disabled" do
      reset!
      Account.find(account.id).update!(live_mode_enabled: false)
      sign_in_as(user)

      # User explicitly switches to production mode via session
      patch dashboard_view_mode_path, params: { mode: "production" }
      follow_redirect!

      # User explicitly chose production, so no banner
      assert_select "[data-testid='test-mode-banner']", count: 0
    end

    private

    def user
      @user ||= users(:one)
    end

    def account
      @account ||= accounts(:one)
    end

    def current_account
      user.primary_account
    end

    def sign_in_as(user)
      post login_path, params: { email: user.email, password: "password123" }
    end

    def logout
      delete logout_path
    end
  end
end
