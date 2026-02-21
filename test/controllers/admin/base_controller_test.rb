# frozen_string_literal: true

require "test_helper"

class Admin::BaseControllerTest < ActionDispatch::IntegrationTest
  test "redirects non-admin users to root" do
    sign_in_as(regular_user)

    get admin_billing_path

    assert_redirected_to root_path
    assert_equal "Access denied.", flash[:alert]
  end

  test "redirects unauthenticated users to login" do
    get admin_billing_path

    assert_redirected_to login_path
  end

  test "allows admin users to access admin pages" do
    sign_in_as(admin_user)

    get admin_billing_path

    assert_response :success
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  def regular_user
    @regular_user ||= users(:one)
  end

  def admin_user
    @admin_user ||= users(:admin)
  end
end
