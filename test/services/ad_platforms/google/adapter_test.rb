# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Google::AdapterTest < ActiveSupport::TestCase
  test "inherits from BaseAdapter" do
    assert_kind_of AdPlatforms::BaseAdapter, adapter
  end

  test "refresh_token! delegates to TokenRefresher" do
    stub_refresher(success: true, access_token: "new_token") do
      result = adapter.refresh_token!

      assert result[:success]
    end
  end

  test "validate_connection refreshes when token expired" do
    connection.update!(token_expires_at: 1.hour.ago)

    stub_refresher(success: true, access_token: "new_token") do
      result = adapter.validate_connection

      assert result[:success]
    end
  end

  test "validate_connection succeeds when token is fresh" do
    connection.update!(token_expires_at: 1.hour.from_now)

    result = adapter.validate_connection

    assert result[:success]
  end

  private

  def adapter = @adapter ||= AdPlatforms::Google::Adapter.new(connection)
  def connection = @connection ||= ad_platform_connections(:google_ads)

  def stub_refresher(response)
    mock = ->(_) { OpenStruct.new(call: response) }

    AdPlatforms::Google::TokenRefresher.stub(:new, mock) do
      yield
    end
  end
end
