# frozen_string_literal: true

require "test_helper"

class SignupControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
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

    assert_redirected_to signup_welcome_path
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

  test "welcome page mounts the gtm-event controller for signup_complete" do
    post signup_path, params: {
      user: { email: "newuser@example.com", password: "password123" },
      account: { name: "New Company" }
    }
    get signup_welcome_path

    assert_response :success
    assert_includes response.body, 'data-controller="gtm-event"'
    assert_includes response.body, 'data-gtm-event-name-value="signup_complete"'
  end

  test "welcome page hashes the user email for the user_id_hashed property" do
    post signup_path, params: {
      user: { email: "Newuser@Example.com", password: "password123" },
      account: { name: "New Company" }
    }
    get signup_welcome_path

    expected_hash = Digest::SHA256.hexdigest("newuser@example.com")

    assert_includes response.body, expected_hash
  end

  test "welcome page redirects to signup when no user is signed in" do
    get signup_welcome_path

    assert_redirected_to signup_path
  end

  test "create enqueues the internal new-signup notification" do
    assert_enqueued_with(job: InternalNotifications::NewSignupJob) do
      post signup_path, params: {
        user: { email: "newuser@example.com", password: "password123" },
        account: { name: "New Company" }
      }
    end
  end

  test "create does not enqueue the notification when signup fails" do
    assert_no_enqueued_jobs(only: InternalNotifications::NewSignupJob) do
      post signup_path, params: {
        user: { email: "invalid", password: "password123" },
        account: { name: "New Company" }
      }
    end
  end
end
