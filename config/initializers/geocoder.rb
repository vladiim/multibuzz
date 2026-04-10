# frozen_string_literal: true

# Geocoder is used as a fallback for the marketing-site consent banner geo
# gating when the CF-IPCountry header is not available. The primary path is
# the Cloudflare header; this only fires when Cloudflare is not in front of
# the request (local dev, direct origin hits, some staging configurations).
#
# In production we use the free Nominatim/OSM IP lookup. In test we use the
# bundled Test lookup so no network calls happen during the suite.
Geocoder.configure(
  ip_lookup: Rails.env.test? ? :test : :ipinfo_io,
  timeout: 1,
  always_raise: :all
)
