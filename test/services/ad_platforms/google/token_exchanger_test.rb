# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Google::TokenExchangerTest < ActiveSupport::TestCase
  test "returns tokens on successful exchange" do
    stub_client(success: true, body: token_body) do
      result = exchanger.call

      assert result[:success]
      assert_equal "access_123", result[:access_token]
      assert_equal "refresh_456", result[:refresh_token]
    end
  end

  test "returns expiry on successful exchange" do
    stub_client(success: true, body: token_body) do
      assert_predicate exchanger.call[:expires_at], :present?
    end
  end

  test "passes through client error" do
    stub_client(success: false, errors: [ "Google OAuth error: Bad Request" ]) do
      result = exchanger.call

      assert_not result[:success]
      assert_includes result[:errors].first, "Bad Request"
    end
  end

  test "returns error when code is nil" do
    result = AdPlatforms::Google::TokenExchanger.new(code: nil).call

    assert_not result[:success]
    assert_includes result[:errors], "Authorization code is required"
  end

  test "returns error when code is blank" do
    result = AdPlatforms::Google::TokenExchanger.new(code: "").call

    assert_not result[:success]
  end

  private

  def exchanger = @exchanger ||= AdPlatforms::Google::TokenExchanger.new(code: "auth_code_xyz")

  def token_body
    { "access_token" => "access_123", "refresh_token" => "refresh_456", "expires_in" => 3600 }
  end

  def stub_client(response)
    mock_client = ->(**, &_) { OpenStruct.new(call: response) }

    AdPlatforms::Google::TokenClient.stub(:new, mock_client) do
      yield
    end
  end
end
