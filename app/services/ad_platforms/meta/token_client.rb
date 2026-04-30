# frozen_string_literal: true

module AdPlatforms
  module Meta
    # Thin HTTP shell. Posts to Meta's token endpoint and returns the parsed body.
    # No business logic — no unit tests. Covered by integration via VCR cassette
    # in the controller layer.
    class TokenClient
      def initialize(params:)
        @params = params
      end

      def call
        response = Net::HTTP.post_form(TOKEN_URI, params)
        JSON.parse(response.body || "{}")
      rescue JSON::ParserError, StandardError => e
        { "error" => { "message" => e.message } }
      end

      private

      attr_reader :params
    end
  end
end
