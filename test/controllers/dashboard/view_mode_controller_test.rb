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

    test "navbar shows test mode toggle when logged in" do
      get dashboard_path

      assert_response :success
      assert_select "form[action='#{dashboard_view_mode_path}']", count: 2
    end

    test "navbar shows Test button active when in test mode" do
      patch dashboard_view_mode_path, params: { mode: "test" }
      follow_redirect!

      assert_select "form[action='#{dashboard_view_mode_path}']" do
        assert_select "button.bg-amber-500", text: "Test"
      end
    end

    test "navbar shows Live button active when in production mode" do
      get dashboard_path

      assert_select "form[action='#{dashboard_view_mode_path}']" do
        assert_select "button.bg-white", text: "Live"
      end
    end

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

    test "defaults to test mode when onboarding is incomplete" do
      # Use user:three who only has one account membership (admin in account:one)
      # This avoids the primary_account ambiguity when a user has multiple memberships
      single_account_user = users(:three)
      target_account = accounts(:one)

      # Start fresh with no view_mode in session
      reset!

      # Reset the account to incomplete onboarding
      target_account.update!(onboarding_progress: 1)
      assert_not target_account.reload.onboarding_complete?, "Account should have incomplete onboarding"

      sign_in_as(single_account_user)
      get dashboard_path

      assert_response :success
      assert_nil session[:view_mode], "Session should not have view_mode set"
      assert_select "[data-testid='test-mode-banner']"
    end

    test "defaults to production mode when onboarding is complete" do
      # Use user:three who only has one account membership (admin in account:one)
      single_account_user = users(:three)
      target_account = accounts(:one)

      # Start fresh with no view_mode in session
      reset!

      # Complete onboarding
      target_account.update!(onboarding_progress: (1 << Account::Onboarding::ONBOARDING_STEPS.size) - 1)

      sign_in_as(single_account_user)
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='test-mode-banner']", count: 0
    end

    test "user can still switch to production mode even with incomplete onboarding" do
      # Start fresh with incomplete onboarding
      reset!
      Account.find(account.id).update!(onboarding_progress: 1)
      sign_in_as(user)

      # User explicitly switches to production mode
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

    def sign_in_as(user)
      post login_path, params: { email: user.email, password: "password123" }
    end

    def logout
      delete logout_path
    end
  end
end
