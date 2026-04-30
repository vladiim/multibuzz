# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Meta::OauthUrlTest < ActiveSupport::TestCase
  test "uses the Facebook OAuth dialog endpoint" do
    assert url.start_with?("https://www.facebook.com/v19.0/dialog/oauth?")
  end

  test "includes the injected client_id" do
    assert_includes url, "client_id=test_client_123"
  end

  test "includes ads_read scope" do
    assert_includes url, "scope=ads_read"
  end

  test "includes the injected redirect_uri" do
    assert_includes url, "redirect_uri=https%3A%2F%2Fmbuzz.co%2Foauth%2Fmeta_ads%2Fcallback"
  end

  test "includes the state parameter" do
    assert_includes url, "state=csrf_token_xyz"
  end

  test "sets response_type to code" do
    assert_includes url, "response_type=code"
  end

  test "raises on blank state" do
    assert_raises(ArgumentError) do
      AdPlatforms::Meta::OauthUrl.new(state: "", client_id: "abc", redirect_uri: "https://x")
    end
  end

  test "raises on nil state" do
    assert_raises(ArgumentError) do
      AdPlatforms::Meta::OauthUrl.new(state: nil, client_id: "abc", redirect_uri: "https://x")
    end
  end

  private

  def url
    @url ||= AdPlatforms::Meta::OauthUrl.new(
      state: "csrf_token_xyz",
      client_id: "test_client_123",
      redirect_uri: "https://mbuzz.co/oauth/meta_ads/callback"
    ).call
  end
end
