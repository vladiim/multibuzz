# frozen_string_literal: true

module AdPlatforms
  module Google
    class ListCustomers
      def initialize(access_token:)
        @access_token = access_token
      end

      def call
        return list_error unless list_response_success?

        { success: true, customers: all_customers }
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

      # --- Discover all selectable accounts ---

      def all_customers
        customer_ids
          .filter_map { |id| fetch_customer_details(id) }
          .flat_map { |details| resolve(details) }
          .uniq { |c| c[:id] }
      end

      def resolve(details)
        return sub_accounts_for(details[:id]) if details[:manager]

        [ details.except(:manager) ]
      end

      def fetch_customer_details(customer_id)
        search(customer_id, query: CUSTOMER_QUERY)
          &.dig(FIELD_RESULTS, 0, FIELD_CUSTOMER)
          &.then { |c| parse_customer(c) }
      end

      def parse_customer(customer)
        {
          id: customer[FIELD_ID],
          name: customer[FIELD_DESCRIPTIVE_NAME],
          currency: customer[FIELD_CURRENCY_CODE],
          manager: customer[FIELD_MANAGER] == true
        }
      end

      # --- MCC sub-account discovery ---

      def sub_accounts_for(manager_id)
        results = search(manager_id, query: SUB_ACCOUNTS_QUERY)&.fetch(FIELD_RESULTS, []) || []
        results.filter_map { |r| parse_client(r) }.map { |c| c.merge(login_customer_id: manager_id) }
      end

      def parse_client(result)
        client = result[FIELD_CUSTOMER_CLIENT]
        return nil if client.nil? || client[FIELD_MANAGER] == true

        { id: client[FIELD_ID], name: client[FIELD_DESCRIPTIVE_NAME], currency: client[FIELD_CURRENCY_CODE] }
      end

      # --- HTTP ---

      def search(customer_id, query:)
        response = api_post(search_uri(customer_id), query: query)
        JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
      end

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
