require "test_helper"

class Accounts::ApiKeysControllerTest < ActionDispatch::IntegrationTest
  test "index renders api keys page" do
    sign_in

    get account_api_keys_path

    assert_response :success
    assert_select "h1", text: /API Keys/i
  end

  test "index displays existing api keys" do
    sign_in

    get account_api_keys_path

    assert_select "table"
  end

  test "create generates new api key" do
    sign_in

    assert_difference "ApiKey.count", 1 do
      post account_api_keys_path, params: { api_key: { environment: "test" } }
    end
  end

  test "destroy revokes api key" do
    sign_in

    delete account_api_key_path(api_key)

    assert api_key.reload.revoked?
  end

  test "requires authentication" do
    get account_api_keys_path

    assert_redirected_to login_path
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

  def api_key
    @api_key ||= api_keys(:one)
  end
end
