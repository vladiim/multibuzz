require "test_helper"

module Dashboard
  class ApiKeysControllerTest < ActionDispatch::IntegrationTest
    test "index requires login" do
      get dashboard_api_keys_path

      assert_redirected_to login_path
      assert_equal "Please log in to continue", flash[:alert]
    end

    test "index shows api keys for current account" do
      login_as(user)

      get dashboard_api_keys_path

      assert_response :success
      assert_select "h1", "API Keys"
    end

    test "index only shows current account's api keys" do
      login_as(user)
      other_account_key = other_account.api_keys.create!(
        key_digest: "other_digest",
        key_prefix: "sk_test_other",
        environment: :test
      )

      get dashboard_api_keys_path

      assert_response :success
      assert_select "td", text: api_key.key_prefix
      assert_select "td", text: other_account_key.key_prefix, count: 0
    end

    test "create generates new api key" do
      login_as(user)

      assert_difference -> { account.api_keys.count }, 1 do
        post dashboard_api_keys_path, params: {
          api_key: { environment: "test", name: "Test Key" }
        }
      end

      assert_response :success
      assert_match /sk_test_/, response.body
      assert_match /Copy it now/, flash[:notice]
    end

    test "create requires environment" do
      login_as(user)

      assert_no_difference -> { account.api_keys.count } do
        post dashboard_api_keys_path, params: {
          api_key: { name: "Test Key" }
        }
      end

      assert_response :unprocessable_entity
    end

    test "destroy revokes api key" do
      login_as(user)

      delete dashboard_api_key_path(api_key)

      assert_redirected_to dashboard_api_keys_path
      assert_equal "API key revoked successfully", flash[:notice]
      assert api_key.reload.revoked?
    end

    test "destroy requires login" do
      delete dashboard_api_key_path(api_key)

      assert_redirected_to login_path
    end

    test "cannot destroy other account's api key" do
      login_as(user)
      other_account_key = other_account.api_keys.create!(
        key_digest: "other_digest",
        key_prefix: "sk_test_other",
        environment: :test
      )

      delete dashboard_api_key_path(other_account_key)

      assert_response :not_found
    end

    private

    def user
      @user ||= users(:one)
    end

    def account
      @account ||= user.account
    end

    def api_key
      @api_key ||= api_keys(:one)
    end

    def other_account
      @other_account ||= accounts(:two)
    end

    def login_as(user)
      post login_path, params: { email: user.email, password: "password123" }
    end
  end
end
