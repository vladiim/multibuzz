# frozen_string_literal: true

module AdPlatforms
  class Registry
    ADAPTERS = {
      google_ads: AdPlatforms::Google::Adapter,
      meta_ads: AdPlatforms::Meta::Adapter
    }.freeze

    CONNECTION_SYNC_SERVICES = {
      google_ads: AdPlatforms::Google::ConnectionSyncService,
      meta_ads: AdPlatforms::Meta::ConnectionSyncService
    }.freeze

    def self.adapter_for(connection)
      adapter_class = ADAPTERS.fetch(connection.platform.to_sym) do
        raise ArgumentError, "No adapter for platform: #{connection.platform}"
      end

      adapter_class.new(connection)
    end

    def self.connection_sync_service_for(platform)
      CONNECTION_SYNC_SERVICES.fetch(platform.to_sym) do
        raise ArgumentError, "No connection sync service for platform: #{platform}"
      end
    end
  end
end
