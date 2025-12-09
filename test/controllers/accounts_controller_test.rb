# frozen_string_literal: true

require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  # --- New ---

  test "new renders create account form" do
    sign_in

    get new_account_path

    assert_response :success
    assert_select "form[action='#{accounts_path}']"
  end

  test "new requires authentication" do
    get new_account_path

    assert_redirected_to login_path
  end

  # --- Create ---

  test "create creates new account and membership" do
    sign_in

    assert_difference ["Account.count", "AccountMembership.count"], 1 do
      post accounts_path, params: { account: { name: "New Company" } }
    end

    new_account = Account.last
    assert_equal "New Company", new_account.name
    assert_equal "new-company", new_account.slug

    membership = new_account.account_memberships.first
    assert_equal user, membership.user
    assert membership.owner?
    assert membership.accepted?
  end

  test "create redirects to new account dashboard" do
    sign_in

    post accounts_path, params: { account: { name: "My Startup" } }

    new_account = Account.last
    assert_redirected_to dashboard_path(account_id: new_account.prefix_id)
    assert_equal "Account created successfully!", flash[:notice]
  end

  test "create renders errors for invalid account" do
    sign_in

    assert_no_difference "Account.count" do
      post accounts_path, params: { account: { name: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "create generates unique slug for duplicate names" do
    sign_in
    Account.create!(name: "Acme", slug: "acme")

    post accounts_path, params: { account: { name: "Acme" } }

    new_account = Account.last
    assert_match(/^acme-\w+$/, new_account.slug)
  end

  test "create requires authentication" do
    post accounts_path, params: { account: { name: "New Company" } }

    assert_redirected_to login_path
  end

  private

  def sign_in
    post login_path, params: { email: user.email, password: "password123" }
  end

  def user
    @user ||= users(:one)
  end
end
