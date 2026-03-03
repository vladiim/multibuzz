# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Google::TokenRefresherTest < ActiveSupport::TestCase
  test "returns new access token on success" do
    stub_client(success: true, body: refresh_body) do
      result = refresher.call

      assert result[:success]
      assert_equal "new_access_token", result[:access_token]
      assert_predicate result[:expires_at], :present?
    end
  end

  test "passes through client error" do
    stub_client(success: false, errors: [ "Google OAuth error: Token revoked" ]) do
      result = refresher.call

      assert_not result[:success]
      assert_includes result[:errors].first, "Token revoked"
    end
  end

  test "returns error when connection has no refresh token" do
    connection.update!(refresh_token: nil)

    result = AdPlatforms::Google::TokenRefresher.new(connection).call

    assert_not result[:success]
    assert_includes result[:errors], "No refresh token available"
  end

  private

  def connection = @connection ||= ad_platform_connections(:google_ads)
  def refresher = @refresher ||= AdPlatforms::Google::TokenRefresher.new(connection)

  def refresh_body
    { "access_token" => "new_access_token", "expires_in" => 3600 }
  end

  def stub_client(response)
    mock_client = ->(**, &_) { OpenStruct.new(call: response) }

    AdPlatforms::Google::TokenClient.stub(:new, mock_client) do
      yield
    end
  end
end
