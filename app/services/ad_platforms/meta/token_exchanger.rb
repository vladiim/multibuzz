# frozen_string_literal: true

module AdPlatforms
  module Meta
    # Pure parser. Takes a Meta token endpoint response body, returns a uniform
    # success/error hash. No HTTP, no IO — fully testable with real-shape hashes.
    class TokenExchanger
      def initialize(body:)
        @body = body
      end

      def call
        return parse_failure_result if body.nil? || !body.is_a?(Hash)
        return error_result if body.key?(FIELD_ERROR)
        return missing_field_result unless access_token

        success_result
      end

      private

      attr_reader :body

      def access_token
        body[FIELD_ACCESS_TOKEN]
      end

      def expires_in
        body[FIELD_EXPIRES_IN].to_i
      end

      def success_result
        { success: true, access_token: access_token, expires_at: Time.current + expires_in.seconds }
      end

      def error_result
        { success: false, errors: [ body.dig(FIELD_ERROR, FIELD_ERROR_MESSAGE) || "Meta API error" ] }
      end

      def missing_field_result
        { success: false, errors: [ "Meta response missing access_token" ] }
      end

      def parse_failure_result
        { success: false, errors: [ "Empty or invalid Meta token response" ] }
      end
    end
  end
end
