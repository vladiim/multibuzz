# frozen_string_literal: true

# Builds a Meta `_fbc` cookie value from an `fbclid` URL parameter and a
# capture timestamp. Used as a server-side fallback when the SDK doesn't
# read the cookie itself.
#
# Meta's documented format:
#   fb.{subdomain_index}.{creation_time_ms}.{fbclid}
#
# - `subdomain_index = 1` means the cookie is set on the second-level
#   domain (the standard case for first-party cookies on a customer's site).
# - `creation_time_ms` is the time the click was observed, expressed as
#   milliseconds since the Unix epoch.
#
# Reference:
# https://developers.facebook.com/docs/marketing-api/conversions-api/parameters/fbp-and-fbc
module Identities
  class FbcCookie
    VERSION = "fb"
    SUBDOMAIN_INDEX = "1"
    MS_PER_SECOND = 1000

    def initialize(fbclid:, captured_at:)
      @fbclid = fbclid
      @captured_at = captured_at
    end

    def to_s
      return nil unless fbclid.present?

      "#{VERSION}.#{SUBDOMAIN_INDEX}.#{captured_at_ms}.#{fbclid}"
    end

    private

    attr_reader :fbclid, :captured_at

    def captured_at_ms = (captured_at.to_f * MS_PER_SECOND).to_i
  end
end
