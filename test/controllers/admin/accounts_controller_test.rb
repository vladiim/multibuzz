# frozen_string_literal: true

require "test_helper"

class Admin::AccountsControllerTest < ActionDispatch::IntegrationTest
  test "show displays account details for admin" do
    sign_in_as(admin_user)

    get admin_account_path(account)

    assert_response :success
    assert_select "h1", text: /#{account.name}/
  end

  test "show displays free_until form" do
    sign_in_as(admin_user)

    get admin_account_path(account)

    assert_response :success
    assert_select "form[action='#{admin_account_path(account)}']"
  end

  test "update grants free_until access" do
    sign_in_as(admin_user)
    future_date = 30.days.from_now.to_date

    patch admin_account_path(account), params: {
      account: { free_until: future_date, plan_id: starter_plan.id }
    }

    assert_redirected_to admin_account_path(account)
    account.reload

    assert_equal :free_until, account.billing_status.to_sym
    assert_equal future_date, account.free_until.to_date
    assert_equal starter_plan, account.plan
  end

  test "update extends existing free_until" do
    account.grant_free_until!(until_date: 30.days.from_now, plan: starter_plan)
    sign_in_as(admin_user)
    new_date = 60.days.from_now.to_date

    patch admin_account_path(account), params: {
      account: { free_until: new_date }
    }

    assert_redirected_to admin_account_path(account)
    account.reload

    assert_equal new_date, account.free_until.to_date
  end

  test "update clears free_until when date is blank" do
    account.grant_free_until!(until_date: 30.days.from_now, plan: starter_plan)
    sign_in_as(admin_user)

    patch admin_account_path(account), params: {
      account: { free_until: "" }
    }

    assert_redirected_to admin_account_path(account)
    account.reload

    assert_equal :free_forever, account.billing_status.to_sym
    assert_nil account.free_until
  end

  test "non-admin cannot access account management" do
    sign_in_as(regular_user)

    get admin_account_path(account)

    assert_redirected_to root_path
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

  def starter_plan
    @starter_plan ||= plans(:starter)
  end
end
