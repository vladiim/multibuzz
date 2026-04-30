# frozen_string_literal: true

module AdPlatforms
  # Surfaces the metadata keys an account has already used on other ad-platform
  # connections, so the connect-time picker can offer them as datalist
  # suggestions. The curated AdPlatformMetadataKeys list is always merged in
  # so first-time users still see Location/Region/Brand/Store.
  class KnownMetadata
    def self.keys_for(account)
      from_existing = account.ad_platform_connections
        .pluck(:metadata)
        .flat_map { |m| m.is_a?(Hash) ? m.keys : [] }

      (AdPlatformMetadataKeys::CURATED + from_existing).uniq.sort
    end
  end
end
