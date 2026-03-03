# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Google::OauthUrlTest < ActiveSupport::TestCase
  test "includes client_id from credentials" do
    assert_includes url, "client_id=test_client_id"
  end

  test "includes adwords scope" do
    assert_includes url, "auth%2Fadwords"
  end

  test "includes state parameter" do
    assert_includes url, "state=csrf_token_123"
  end

  test "includes redirect_uri" do
    assert_includes url, "redirect_uri="
  end

  test "sets access_type to offline" do
    assert_includes url, "access_type=offline"
  end

  test "sets prompt to consent" do
    assert_includes url, "prompt=consent"
  end

  test "raises on nil state" do
    assert_raises(ArgumentError) { AdPlatforms::Google::OauthUrl.new(state: nil).call }
  end

  test "raises on blank state" do
    assert_raises(ArgumentError) { AdPlatforms::Google::OauthUrl.new(state: "").call }
  end

  private

  def url
    @url ||= AdPlatforms::Google.stub(:credentials, test_credentials) do
      AdPlatforms::Google::OauthUrl.new(state: "csrf_token_123").call
    end
  end

  def test_credentials
    { client_id: "test_client_id", client_secret: "test_client_secret" }
  end
end
