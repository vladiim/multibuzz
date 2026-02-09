require "test_helper"

class Admin::DataIntegrityControllerTest < ActionDispatch::IntegrationTest
  test "non-admin gets redirected" do
    sign_in_as(regular_user)

    get admin_data_integrity_index_path

    assert_response :redirect
  end

  test "index renders for admin" do
    sign_in_as(admin_user)

    get admin_data_integrity_index_path

    assert_response :success
    assert_select "h1", text: "Data Integrity"
  end

  test "index shows accounts with health status" do
    sign_in_as(admin_user)

    get admin_data_integrity_index_path

    assert_response :success
    assert_select "[data-testid='accounts-table']"
  end

  test "show renders for admin" do
    sign_in_as(admin_user)

    get admin_data_integrity_path(account)

    assert_response :success
    assert_select "h1", text: /#{account.name}/
  end

  test "show displays check results" do
    sign_in_as(admin_user)

    get admin_data_integrity_path(account)

    assert_response :success
    assert_select "[data-testid='checks-table']"
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  def admin_user
    @admin_user ||= users(:admin)
  end

  def regular_user
    @regular_user ||= users(:one)
  end

  def account
    @account ||= accounts(:one)
  end
end
