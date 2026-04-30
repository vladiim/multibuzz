# frozen_string_literal: true

module AdPlatforms
  class Registry
    ADAPTERS = {
      google_ads: AdPlatforms::Google::Adapter,
      meta_ads: AdPlatforms::Meta::Adapter
    }.freeze

    def self.adapter_for(connection)
      adapter_class = ADAPTERS.fetch(connection.platform.to_sym) do
        raise ArgumentError, "No adapter for platform: #{connection.platform}"
      end

      adapter_class.new(connection)
    end
  end
end
