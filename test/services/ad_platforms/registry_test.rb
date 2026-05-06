# frozen_string_literal: true

require "test_helper"

class AdPlatforms::RegistryTest < ActiveSupport::TestCase
  test "adapter_for returns Google adapter for google_ads connection" do
    connection = ad_platform_connections(:google_ads)
    adapter = AdPlatforms::Registry.adapter_for(connection)

    assert_kind_of AdPlatforms::Google::Adapter, adapter
  end

  test "adapter_for raises for unregistered platform" do
    connection = ad_platform_connections(:google_ads)
    connection.update_column(:platform, AdPlatformConnection.platforms[:linkedin_ads])

    assert_raises(ArgumentError) { AdPlatforms::Registry.adapter_for(connection) }
  end

  test "connection_sync_service_for returns Google sync service for google_ads" do
    klass = AdPlatforms::Registry.connection_sync_service_for(:google_ads)

    assert_equal AdPlatforms::Google::ConnectionSyncService, klass
  end

  test "connection_sync_service_for returns Meta sync service for meta_ads" do
    klass = AdPlatforms::Registry.connection_sync_service_for(:meta_ads)

    assert_equal AdPlatforms::Meta::ConnectionSyncService, klass
  end

  test "connection_sync_service_for raises for unknown platform" do
    assert_raises(ArgumentError) { AdPlatforms::Registry.connection_sync_service_for(:unknown_platform) }
  end

  test "connection_sync_service_for accepts string and symbol" do
    assert_equal AdPlatforms::Google::ConnectionSyncService,
                 AdPlatforms::Registry.connection_sync_service_for("google_ads")
  end
end
