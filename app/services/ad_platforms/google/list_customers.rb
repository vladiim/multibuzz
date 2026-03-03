# frozen_string_literal: true

module AdPlatforms
  module Google
    class ListCustomers
      def initialize(access_token:)
        @access_token = access_token
      end

      def call
        return list_error unless list_response_success?

        { success: true, customers: non_manager_customers }
      end

      private

      attr_reader :access_token

      # --- List accessible customers ---

      def list_response_success?
        list_response.is_a?(Net::HTTPSuccess)
      end

      def list_response
        @list_response ||= api_get(LIST_CUSTOMERS_URI)
      end

      def customer_ids
        parsed_list.fetch(FIELD_RESOURCE_NAMES, []).map { |rn| rn.split("/").last }
      end

      def parsed_list
        @parsed_list ||= JSON.parse(list_response.body)
      end

      # --- Fetch details per customer ---

      def non_manager_customers
        customer_ids.filter_map { |id| fetch_customer(id) }
      end

      def fetch_customer(customer_id)
        response = api_post(search_uri(customer_id), query: CUSTOMER_QUERY)
        return nil unless response.is_a?(Net::HTTPSuccess)

        parse_customer(JSON.parse(response.body))
      end

      def parse_customer(body)
        customer = body.dig(FIELD_RESULTS, 0, FIELD_CUSTOMER)
        return nil if customer.nil? || customer[FIELD_MANAGER] == true

        {
          id: customer[FIELD_ID],
          name: customer[FIELD_DESCRIPTIVE_NAME],
          currency: customer[FIELD_CURRENCY_CODE]
        }
      end

      # --- HTTP ---

      def search_uri(customer_id)
        URI("#{API_BASE_URL}/#{API_VERSION}/customers/#{customer_id}/#{SEARCH_PATH}")
      end

      def api_get(uri)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(build_request(Net::HTTP::Get, uri))
        end
      end

      def api_post(uri, body)
        Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          request = build_request(Net::HTTP::Post, uri)
          request.body = body.to_json
          http.request(request)
        end
      end

      def build_request(klass, uri)
        klass.new(uri).tap do |req|
          req["Authorization"] = "Bearer #{access_token}"
          req[HEADER_DEVELOPER_TOKEN] = Google.credentials.fetch(:developer_token)
          req.content_type = "application/json"
        end
      end

      def list_error
        { success: false, errors: [ "Failed to list Google Ads accounts" ] }
      end
    end
  end
end
