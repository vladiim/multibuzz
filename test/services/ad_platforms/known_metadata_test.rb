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

  private

  def account = @account ||= accounts(:one)
end
