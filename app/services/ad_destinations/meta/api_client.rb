# frozen_string_literal: true

# Thin HTTP wrapper around Meta's Conversions API. POSTs a payload to
# graph.facebook.com/{API_VERSION}/{pixel_id}/events with the customer
# Pixel's access_token as a query parameter, parses the JSON body, and
# returns an `AdDestinations::Meta::Result` so the dispatcher can route
# success / auth-failure / transient / permanent without inspecting
# status codes itself.
#
# **No appsecret_proof in v1** — the auto-created CAPI app secret is
# owned by the customer's BM, not mbuzz, so we can't compute it without
# the customer sharing it. Bare token works. See
# lib/specs/conversion_feedback_spec.md Phase 0B.3.
module AdDestinations
  module Meta
    class ApiClient
      USAGE_TRACKER_KEY = :meta_capi
      JSON_CONTENT_TYPE = "application/json"
      ACCESS_TOKEN_QUERY_KEY = "access_token"

      def initialize(destination)
        @destination = destination
      end

      def post(payload)
        response = http_post(payload)
        AdPlatforms::ApiUsageTracker.increment!(USAGE_TRACKER_KEY)
        Result.new(http_status: response.code.to_i, body: parse_body(response))
      end

      private

      attr_reader :destination

      def http_post(payload)
        Net::HTTP.post(events_uri, payload.to_json, "Content-Type" => JSON_CONTENT_TYPE)
      end

      def events_uri
        URI("#{Platforms::Meta::Capi::GRAPH_HOST}/#{Platforms::Meta::Capi::API_VERSION}/#{destination.meta_pixel_id}/events").tap do |uri|
          uri.query = URI.encode_www_form(ACCESS_TOKEN_QUERY_KEY => destination.meta_access_token)
        end
      end

      def parse_body(response)
        JSON.parse(response.body || "{}")
      rescue JSON::ParserError
        {}
      end
    end
  end
end
