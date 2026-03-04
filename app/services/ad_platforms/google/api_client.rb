# frozen_string_literal: true

module AdPlatforms
  module Google
    class ApiClient
      def initialize(access_token:, customer_id: nil, login_customer_id: nil)
        @access_token = access_token
        @customer_id = customer_id
        @login_customer_id = login_customer_id
      end

      def search(query)
        response = post(search_uri, { query: query })
        return {} unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      def get(uri)
        execute(Net::HTTP::Get, uri)
      end

      def post(uri, body)
        execute(Net::HTTP::Post, uri) { |req| req.body = body.to_json }
      end

      private

      attr_reader :access_token, :customer_id, :login_customer_id

      def execute(klass, uri)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          request = build_request(klass, uri)
          yield request if block_given?
          http.request(request)
        end
      end

      def build_request(klass, uri)
        klass.new(uri).tap do |req|
          req["Authorization"] = "Bearer #{access_token}"
          req[HEADER_DEVELOPER_TOKEN] = Google.credentials.fetch(:developer_token)
          req[HEADER_LOGIN_CUSTOMER_ID] = login_customer_id if login_customer_id.present?
          req.content_type = "application/json"
        end
      end

      def search_uri
        @search_uri ||= URI("#{API_BASE_URL}/#{API_VERSION}/customers/#{customer_id}/#{SEARCH_PATH}")
      end
    end
  end
end
