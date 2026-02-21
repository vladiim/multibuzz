# frozen_string_literal: true

require "test_helper"

class SignupControllerTest < ActionDispatch::IntegrationTest
  test "new renders signup form" do
    get signup_path

    assert_response :success
    assert_select "form"
    assert_select "input[name='user[email]']"
    assert_select "input[name='user[password]']"
    assert_select "input[name='account[name]']"
  end

  test "create with valid params creates user and account" do
    assert_difference [ "User.count", "Account.count", "AccountMembership.count" ], 1 do
      post signup_path, params: {
        user: { email: "newuser@example.com", password: "password123" },
        account: { name: "New Company" }
      }
    end

    assert_redirected_to onboarding_path
  end

  test "create logs in the new user" do
    post signup_path, params: {
      user: { email: "newuser@example.com", password: "password123" },
      account: { name: "New Company" }
    }

    assert_predicate session[:user_id], :present?
  end

  test "create sets user as account owner" do
    post signup_path, params: {
      user: { email: "newuser@example.com", password: "password123" },
      account: { name: "New Company" }
    }

    user = User.find_by(email: "newuser@example.com")
    account = Account.find_by(name: "New Company")
    membership = AccountMembership.find_by(user: user, account: account)

    assert_predicate membership, :owner?
    assert_predicate membership, :accepted?
  end

  test "create with invalid email rerenders form" do
    assert_no_difference [ "User.count", "Account.count" ] do
      post signup_path, params: {
        user: { email: "invalid", password: "password123" },
        account: { name: "New Company" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create with blank password rerenders form" do
    assert_no_difference [ "User.count", "Account.count" ] do
      post signup_path, params: {
        user: { email: "newuser@example.com", password: "" },
        account: { name: "New Company" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create with blank account name rerenders form" do
    assert_no_difference [ "User.count", "Account.count" ] do
      post signup_path, params: {
        user: { email: "newuser@example.com", password: "password123" },
        account: { name: "" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create with duplicate email rerenders form" do
    existing_user = users(:one)

    assert_no_difference [ "User.count", "Account.count" ] do
      post signup_path, params: {
        user: { email: existing_user.email, password: "password123" },
        account: { name: "New Company" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create creates test API key for new account" do
    post signup_path, params: {
      user: { email: "newuser@example.com", password: "password123" },
      account: { name: "New Company" }
    }

    account = Account.find_by(name: "New Company")

    assert_predicate account.api_keys.test, :exists?
  end
end
