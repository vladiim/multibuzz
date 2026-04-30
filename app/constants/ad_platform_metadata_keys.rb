# frozen_string_literal: true

# Curated suggestions for ad-platform connection metadata keys. Surfaced as
# dropdown hints on the connect-time picker so users converge on a small set
# of consistent keys (location, region, brand, store) instead of inventing
# variants. Users can still type any new key.
#
# Stored lowercased to match SDK convention (`properties: { location: ... }`).
module AdPlatformMetadataKeys
  LOCATION = "location"
  REGION = "region"
  BRAND = "brand"
  STORE = "store"

  CURATED = [ LOCATION, REGION, BRAND, STORE ].freeze
end
