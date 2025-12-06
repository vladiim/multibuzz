require "test_helper"

class Admin::BillingControllerTest < ActionDispatch::IntegrationTest
  test "show displays billing metrics for admin" do
    sign_in_as(admin_user)

    get admin_billing_path

    assert_response :success
    assert_select "h1", text: "Billing Admin"
  end

  test "show displays MRR" do
    sign_in_as(admin_user)
    create_paying_account

    get admin_billing_path

    assert_response :success
    assert_select "[data-testid='mrr']"
  end

  test "show displays account counts" do
    sign_in_as(admin_user)

    get admin_billing_path

    assert_response :success
    assert_select "[data-testid='account-counts']"
  end

  test "show lists accounts for free_until management" do
    sign_in_as(admin_user)

    get admin_billing_path

    assert_response :success
    assert_select "[data-testid='accounts-table']"
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  def admin_user
    @admin_user ||= users(:admin)
  end

  def create_paying_account
    Account.create!(
      name: "Paying Account",
      slug: "paying-#{SecureRandom.hex(4)}",
      billing_status: :active,
      plan: plans(:starter)
    )
  end
end
