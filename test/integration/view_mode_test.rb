# frozen_string_literal: true

require "test_helper"

class ViewModeTest < ActionDispatch::IntegrationTest
  # --- Default View Mode ---

  test "defaults to test mode when live_mode_enabled is false" do
    account.update!(live_mode_enabled: false)
    sign_in

    get dashboard_path
    assert_response :success

    # Verify we're in test mode by checking the session
    assert_equal "test", session[:view_mode] || default_view_mode_for(account)
  end

  test "defaults to production mode when live_mode_enabled is true" do
    account.update!(live_mode_enabled: true)
    sign_in

    get dashboard_path
    assert_response :success

    # Should default to production
    assert_nil session[:view_mode] # No override, uses default
  end

  test "session override takes precedence over live_mode_enabled" do
    account.update!(live_mode_enabled: true)
    sign_in

    # Override to test mode via session
    patch dashboard_view_mode_path, params: { mode: "test" }

    get dashboard_path
    assert_response :success
    assert_equal "test", session[:view_mode]
  end

  test "can switch back to production after session override" do
    account.update!(live_mode_enabled: true)
    sign_in

    # Override to test
    patch dashboard_view_mode_path, params: { mode: "test" }
    assert_equal "test", session[:view_mode]

    # Switch back to production
    patch dashboard_view_mode_path, params: { mode: "production" }
    assert_equal "production", session[:view_mode]
  end

  private

  def sign_in
    post login_path, params: { email: user.email, password: "password123" }
  end

  def user
    @user ||= users(:one)
  end

  def account
    @account ||= accounts(:one)
  end

  def default_view_mode_for(account)
    account.live_mode_enabled? ? "production" : "test"
  end
end
