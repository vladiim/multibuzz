# frozen_string_literal: true

require "test_helper"

class AdPlatforms::KnownMetadataTest < ActiveSupport::TestCase
  test "returns curated keys when account has no connections" do
    keys = AdPlatforms::KnownMetadata.keys_for(account)

    assert_equal AdPlatformMetadataKeys::CURATED.sort, keys
  end

  test "merges curated keys with keys used by existing connections" do
    account.ad_platform_connections.update_all(metadata: { "channel" => "Search", "location" => "Sydney" })

    keys = AdPlatforms::KnownMetadata.keys_for(account)

    assert_includes keys, "channel"
    assert_includes keys, "location"
    assert_includes keys, "region"
  end

  test "values_by_key_for groups values per key across connections" do
    account.ad_platform_connections.first.update!(metadata: { "location" => "Sydney" })
    other = AdPlatformConnection.create!(
      account: account, platform: :meta_ads, platform_account_id: "act_xx", platform_account_name: "x",
      currency: "AUD", access_token: "t", refresh_token: "t",
      token_expires_at: 1.day.from_now, status: :connected, metadata: { "location" => "Brisbane", "brand" => "Premium" }
    )

    grouped = AdPlatforms::KnownMetadata.values_by_key_for(account)

    assert_equal [ "Brisbane", "Sydney" ], grouped["location"]
    assert_equal [ "Premium" ], grouped["brand"]
  end

  test "values_by_key_for is empty when no connections have metadata" do
    grouped = AdPlatforms::KnownMetadata.values_by_key_for(account)

    assert_equal({}, grouped)
  end

  private

  def account = @account ||= accounts(:one)
end
