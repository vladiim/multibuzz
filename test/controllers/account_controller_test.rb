require "test_helper"

class AccountControllerTest < ActionDispatch::IntegrationTest
  test "show renders general settings" do
    sign_in

    get account_path

    assert_response :success
    assert_select "h1", text: /General/i
  end

  test "show displays account name field" do
    sign_in

    get account_path

    assert_select "input[name='account[name]'][value='#{account.name}']"
  end

  test "show displays billing email field" do
    account.update!(billing_email: "billing@example.com")
    sign_in

    get account_path

    assert_select "input[name='account[billing_email]'][value='billing@example.com']"
  end

  test "show displays account prefix_id as read-only" do
    sign_in

    get account_path

    assert_select "p", text: /#{account.prefix_id}/
  end

  test "update changes account name" do
    sign_in

    patch account_path, params: { account: { name: "New Name" } }

    assert_redirected_to account_path
    assert_equal "New Name", account.reload.name
  end

  test "update changes billing email" do
    sign_in

    patch account_path, params: { account: { billing_email: "new@example.com" } }

    assert_redirected_to account_path
    assert_equal "new@example.com", account.reload.billing_email
  end

  test "update with invalid data renders errors" do
    sign_in

    patch account_path, params: { account: { name: "" } }

    assert_response :unprocessable_entity
  end

  test "show displays side navigation" do
    sign_in

    get account_path

    assert_select "nav a", text: "General"
    assert_select "nav a", text: "Billing"
    assert_select "nav a", text: "Team"
    assert_select "nav a", text: "API Keys"
  end

  test "requires authentication" do
    get account_path

    assert_redirected_to login_path
  end

  # --- Live Mode Toggle ---

  test "update enables live mode" do
    sign_in

    patch account_path, params: { account: { live_mode_enabled: true } }

    assert_redirected_to account_path
    assert account.reload.live_mode_enabled?
    assert_equal "Live mode enabled. Dashboard now shows production data.", flash[:notice]
  end

  test "update disables live mode" do
    sign_in
    account.update!(live_mode_enabled: true)

    patch account_path, params: { account: { live_mode_enabled: false } }

    assert_redirected_to account_path
    assert_not account.reload.live_mode_enabled?
    assert_equal "Test mode enabled. Dashboard now shows test data.", flash[:notice]
  end

  test "live mode persists across sessions" do
    sign_in
    account.update!(live_mode_enabled: true)

    # Logout and login again
    delete logout_path
    sign_in

    get dashboard_path
    assert_response :success
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
end
