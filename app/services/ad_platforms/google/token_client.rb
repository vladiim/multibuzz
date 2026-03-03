# frozen_string_literal: true

module AdPlatforms
  module Google
    class TokenClient
      def initialize(**params)
        @params = params
      end

      def call
        return success_result if response_success?

        error_result
      end

      private

      attr_reader :params

      def response_success?
        response.is_a?(Net::HTTPSuccess)
      end

      def response
        @response ||= Net::HTTP.start(TOKEN_URI.hostname, TOKEN_URI.port, use_ssl: true) do |http|
          http.request(request)
        end
      end

      def request
        Net::HTTP::Post.new(TOKEN_URI).tap { |r| r.set_form_data(request_params) }
      end

      def request_params
        params.merge(
          client_id: Google.credentials.fetch(:client_id),
          client_secret: Google.credentials.fetch(:client_secret)
        )
      end

      def parsed_body
        @parsed_body ||= JSON.parse(response.body)
      end

      def success_result
        { success: true, body: parsed_body }
      end

      def error_result
        { success: false, errors: [ error_message ] }
      end

      def error_message
        "Google OAuth error: #{parsed_body["error_description"] || parsed_body["error"]}"
      rescue JSON::ParserError
        "Google OAuth error: unexpected response"
      end
    end
  end
end
