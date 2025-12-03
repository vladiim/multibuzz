require "test_helper"
require "ostruct"

class Dashboard::BillingControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(user)
    account.update!(stripe_customer_id: "cus_test123")
    starter_plan.update!(stripe_price_id: "price_test123")
  end

  # Checkout action tests
  test "checkout redirects back with error for nonexistent plan" do
    post dashboard_billing_checkout_path, params: { plan_slug: "nonexistent" }

    assert_redirected_to dashboard_path
    assert_equal "Plan not found", flash[:alert]
  end

  test "checkout redirects back with error for free plan" do
    post dashboard_billing_checkout_path, params: { plan_slug: "free" }

    assert_redirected_to dashboard_path
    assert_equal "Cannot checkout free plan", flash[:alert]
  end

  test "checkout requires authentication" do
    sign_out

    post dashboard_billing_checkout_path, params: { plan_slug: "starter" }

    assert_redirected_to login_path
  end

  # Portal action tests
  test "portal redirects back with error when no billing account" do
    account.update!(stripe_customer_id: nil)

    get dashboard_billing_portal_path

    assert_redirected_to dashboard_path
    assert_equal "No billing account found", flash[:alert]
  end

  test "portal requires authentication" do
    sign_out

    get dashboard_billing_portal_path

    assert_redirected_to login_path
  end

  # Success action tests
  test "success shows success page" do
    get dashboard_billing_success_path, params: { session_id: "cs_test123" }

    assert_response :success
  end

  test "success requires authentication" do
    sign_out

    get dashboard_billing_success_path, params: { session_id: "cs_test123" }

    assert_redirected_to login_path
  end

  # Cancel action tests
  test "cancel redirects to dashboard" do
    get dashboard_billing_cancel_path

    assert_redirected_to dashboard_path
    assert_equal "Checkout cancelled", flash[:notice]
  end

  test "cancel requires authentication" do
    sign_out

    get dashboard_billing_cancel_path

    assert_redirected_to login_path
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  def sign_out
    delete logout_path
  end

  def user
    @user ||= users(:one)
  end

  def account
    @account ||= accounts(:one)
  end

  def starter_plan
    @starter_plan ||= plans(:starter)
  end
end
