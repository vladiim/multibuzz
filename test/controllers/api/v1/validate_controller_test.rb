require "test_helper"

class Api::V1::ValidateControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
  end

  test "should return valid with correct api key" do
    get api_v1_validate_path, headers: auth_headers

    assert_response :success
    assert json_response["valid"]
    assert_equal account.prefix_id, json_response["account_id"]
    assert_equal api_key.environment, json_response["environment"]
  end

  test "should return 401 without authorization header" do
    get api_v1_validate_path

    assert_response :unauthorized
    assert_equal "Missing Authorization header", json_response["error"]
  end

  test "should return 401 with invalid api key" do
    get api_v1_validate_path, headers: invalid_auth_headers

    assert_response :unauthorized
    assert_equal "Invalid or expired API key", json_response["error"]
  end

  test "should return 401 with revoked api key" do
    api_key.revoke!

    get api_v1_validate_path, headers: auth_headers

    assert_response :unauthorized
    assert_equal "API key has been revoked", json_response["error"]
  end

  test "should record api key usage" do
    old_time = api_key.last_used_at

    get api_v1_validate_path, headers: auth_headers

    assert_response :success
    assert api_key.reload.last_used_at > old_time
  end

  private

  def json_response
    JSON.parse(response.body)
  end

  def auth_headers
    { "Authorization" => "Bearer #{plaintext_key}" }
  end

  def invalid_auth_headers
    { "Authorization" => "Bearer sk_test_invalid123" }
  end

  def account
    @account ||= accounts(:one)
  end

  def api_key
    @api_key ||= api_keys(:one)
  end

  def plaintext_key
    @plaintext_key ||= begin
      key = "sk_test_#{SecureRandom.hex(16)}"
      api_key.update_column(:key_digest, Digest::SHA256.hexdigest(key))
      key
    end
  end
end
