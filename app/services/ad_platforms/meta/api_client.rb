# frozen_string_literal: true

module AdPlatforms
  module Meta
    # Thin HTTP wrapper around the Meta Graph API. Adds access_token +
    # appsecret_proof to every request as Meta recommends. No business logic —
    # callers handle parsing the JSON body.
    #
    # Test posture: integration via VCR cassettes in the orchestrators that use
    # it (ListAdAccounts, SpendSyncService). No unit tests at this layer.
    class ApiClient
      def initialize(access_token:)
        @access_token = access_token
      end

      def get(uri, query: {})
        full_uri = build_uri(uri, query)
        response = Net::HTTP.get_response(full_uri)
        AdPlatforms::ApiUsageTracker.increment!(:meta_ads)
        parse(response)
      end

      private

      attr_reader :access_token

      def build_uri(uri, extra_query)
        base = uri.is_a?(URI) ? uri.dup : URI(uri.to_s)
        merged = URI.decode_www_form(base.query.to_s).to_h.merge(extra_query.transform_keys(&:to_s))
        merged["access_token"] = access_token
        merged["appsecret_proof"] = appsecret_proof
        base.query = URI.encode_www_form(merged)
        base
      end

      def appsecret_proof
        OpenSSL::HMAC.hexdigest("SHA256", Meta.credentials.fetch(:app_secret), access_token)
      end

      def parse(response)
        return { "error" => { "message" => "HTTP #{response.code}" } } unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body || "{}")
      rescue JSON::ParserError => e
        { "error" => { "message" => "Invalid JSON: #{e.message}" } }
      end
    end
  end
end
