# frozen_string_literal: true

require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "successful login increments sign_in_count" do
    post login_path, params: { email: user.email, password: "password123" }

    assert_equal 1, user.reload.sign_in_count
  end

  test "successful login stamps last_sign_in_at" do
    freeze_time do
      post login_path, params: { email: user.email, password: "password123" }

      assert_equal Time.current, user.reload.last_sign_in_at
    end
  end

  test "failed login does not bump login counters" do
    post login_path, params: { email: user.email, password: "wrong-password" }

    assert_equal 0, user.reload.sign_in_count
    assert_nil user.reload.last_sign_in_at
  end

  test "two successful logins yield sign_in_count of 2" do
    2.times { post login_path, params: { email: user.email, password: "password123" } }

    assert_equal 2, user.reload.sign_in_count
  end

  private

  def user = @user ||= users(:one)
end
