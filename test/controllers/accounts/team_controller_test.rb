require "test_helper"

class Accounts::TeamControllerTest < ActionDispatch::IntegrationTest
  test "show renders placeholder" do
    sign_in

    get account_team_path

    assert_response :success
    assert_select "p", text: /coming soon/i
  end

  test "requires authentication" do
    get account_team_path

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
