require "test_helper"

class ApiKeys::AuthenticationServiceTest < ActiveSupport::TestCase
  test "should authenticate valid API key" do
    result = service(valid_bearer_token).call

    assert result[:success]
    assert_equal account, result[:account]
    assert_equal api_key, result[:api_key]
  end

  test "should extract key from Bearer token" do
    result = service("Bearer #{plaintext_key}").call

    assert result[:success]
    assert_equal account, result[:account]
  end

  test "should handle Bearer token with different casing" do
    result = service("bearer #{plaintext_key}").call

    assert result[:success]
  end

  test "should reject missing authorization header" do
    result = service(nil).call

    assert_not result[:success]
    assert_equal :missing_header, result[:error_code]
    assert_includes result[:error], "Missing Authorization header"
  end

  test "should reject empty authorization header" do
    result = service("").call

    assert_not result[:success]
    assert_equal :missing_header, result[:error_code]
  end

  test "should reject malformed header without Bearer prefix" do
    result = service(plaintext_key).call

    assert_not result[:success]
    assert_equal :malformed_header, result[:error_code]
    assert_includes result[:error], "must be in format"
  end

  test "should reject invalid API key" do
    result = service("Bearer sk_test_invalid_key_12345678").call

    assert_not result[:success]
    assert_equal :invalid_key, result[:error_code]
    assert_includes result[:error], "Invalid or expired API key"
  end

  test "should reject revoked API key" do
    revoked_key = api_keys(:revoked)
    revoked_plaintext = "sk_test_revoked123"
    result = service("Bearer #{revoked_plaintext}").call

    assert_not result[:success]
    assert_equal :revoked_key, result[:error_code]
    assert_includes result[:error], "revoked"
  end

  test "should update last_used_at timestamp" do
    api_key.update_column(:last_used_at, nil)

    service(valid_bearer_token).call

    assert api_key.reload.last_used_at.present?
    assert_in_delta Time.current, api_key.last_used_at, 1.second
  end

  test "should handle whitespace in header" do
    result = service("  Bearer  #{plaintext_key}  ").call

    assert result[:success]
  end

  test "should return account for valid key" do
    result = service(valid_bearer_token).call

    assert_instance_of Account, result[:account]
    assert result[:account].persisted?
  end

  test "should work with live API keys" do
    live_key = api_keys(:live)
    live_plaintext = "sk_live_xyz789abc123"
    result = service("Bearer #{live_plaintext}").call

    assert result[:success]
    assert_equal account, result[:account]
    assert live_key.reload.last_used_at.present?
  end

  private

  def service(authorization_header)
    @service ||= {}
    @service[authorization_header] ||= ApiKeys::AuthenticationService.new(authorization_header)
  end

  def api_key
    @api_key ||= api_keys(:one)
  end

  def account
    @account ||= accounts(:one)
  end

  def plaintext_key
    @plaintext_key ||= "sk_test_abc123xyz789"
  end

  def valid_bearer_token
    @valid_bearer_token ||= "Bearer #{plaintext_key}"
  end
end
