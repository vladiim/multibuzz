# frozen_string_literal: true

require "test_helper"

class Accounts::BillingControllerTest < ActionDispatch::IntegrationTest
  test "show renders billing page" do
    sign_in

    get account_billing_path

    assert_response :success
    assert_select "h1", text: /Billing/i
  end

  test "show displays current plan for active subscriber" do
    account.update!(plan: starter_plan, billing_status: :active)
    sign_in

    get account_billing_path

    assert_select "h3", text: /Starter/
  end

  test "show displays billing status badge" do
    account.update!(plan: starter_plan, billing_status: :active)
    sign_in

    get account_billing_path

    assert_select "[data-testid='status-badge']", text: /Active/i
  end

  test "show displays usage progress bar" do
    account.update!(plan: starter_plan, billing_status: :active)
    sign_in

    get account_billing_path

    assert_select "[data-testid='usage-progress']"
  end

  test "show displays manage subscription for active subscribers" do
    account.update!(
      plan: starter_plan,
      billing_status: :active,
      stripe_subscription_id: "sub_123"
    )
    sign_in

    get account_billing_path

    assert_select "a[href='#{portal_account_billing_path}']"
  end

  test "show hides manage subscription for non-subscribers" do
    account.update!(billing_status: :free_forever)
    sign_in

    get account_billing_path

    assert_select "a[href='#{portal_account_billing_path}']", count: 0
  end

  test "show displays upgrade options for free accounts" do
    account.update!(billing_status: :free_forever)
    sign_in

    get account_billing_path

    assert_select "form[action='#{checkout_account_billing_path}']"
  end

  test "show hides upgrade for accounts on highest plan" do
    account.update!(plan: pro_plan, billing_status: :active, stripe_subscription_id: "sub_123")
    sign_in

    get account_billing_path

    assert_select "form[action='#{checkout_account_billing_path}']", count: 0
  end

  test "checkout redirects to stripe" do
    account.update!(stripe_customer_id: "cus_123")
    sign_in

    post checkout_account_billing_path, params: { plan_slug: "starter" }

    assert_response :redirect
  end

  test "portal redirects to stripe portal" do
    account.update!(stripe_customer_id: "cus_123", stripe_subscription_id: "sub_123")
    sign_in

    get portal_account_billing_path

    assert_response :redirect
  end

  test "success renders success page" do
    sign_in

    get success_account_billing_path(session_id: "cs_123")

    assert_response :success
  end

  test "cancel redirects to billing with notice" do
    sign_in

    get cancel_account_billing_path

    assert_redirected_to account_billing_path
  end

  test "requires authentication" do
    get account_billing_path

    assert_redirected_to login_path
  end

  # --- Authorization ---

  test "member cannot access show" do
    sign_in_as_member

    get account_billing_path

    assert_response :forbidden
  end

  test "member cannot initiate checkout" do
    sign_in_as_member

    post checkout_account_billing_path, params: { plan_slug: "starter" }

    assert_response :forbidden
  end

  test "member cannot access portal" do
    sign_in_as_member

    get portal_account_billing_path

    assert_response :forbidden
  end

  test "admin can access show" do
    sign_in_as_admin

    get account_billing_path

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

  def starter_plan
    @starter_plan ||= plans(:starter)
  end

  def pro_plan
    @pro_plan ||= plans(:pro)
  end

  def sign_in_as_member
    post login_path, params: { email: member_user.email, password: "password123" }
  end

  def sign_in_as_admin
    post login_path, params: { email: admin_user.email, password: "password123" }
  end

  def member_user
    @member_user ||= users(:four)
  end

  def admin_user
    @admin_user ||= users(:three)
  end
end
