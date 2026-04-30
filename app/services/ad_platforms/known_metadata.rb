# frozen_string_literal: true

module AdPlatforms
  # Surfaces the metadata keys + values that an account has already used on
  # other ad-platform connections, so the connect-time picker can offer them
  # as dropdown suggestions. The curated AdPlatformMetadataKeys list is
  # always merged in so first-time users still see Location/Region/Brand/Store.
  class KnownMetadata
    def self.keys_for(account)
      from_existing = account.ad_platform_connections
        .pluck(:metadata)
        .flat_map { |m| m.is_a?(Hash) ? m.keys : [] }

      (AdPlatformMetadataKeys::CURATED + from_existing).uniq.sort
    end

    def self.values_by_key_for(account)
      account.ad_platform_connections
        .pluck(:metadata)
        .each_with_object({}) do |metadata, out|
          next unless metadata.is_a?(Hash)
          metadata.each { |k, v| (out[k] ||= []) << v }
        end
        .transform_values { |values| values.uniq.sort }
    end
  end
end
