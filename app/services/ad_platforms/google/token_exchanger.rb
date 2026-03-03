# frozen_string_literal: true

module AdPlatforms
  module Google
    class TokenExchanger
      def initialize(code:)
        @code = code
      end

      def call
        return missing_code_error if code.blank?
        return client_result unless client_result[:success]

        build_tokens
      end

      private

      attr_reader :code

      def client_result
        @client_result ||= TokenClient.new(
          grant_type: GRANT_AUTHORIZATION_CODE,
          code: code,
          redirect_uri: Google.redirect_uri
        ).call
      end

      def build_tokens
        {
          success: true,
          access_token: body.fetch("access_token"),
          refresh_token: body.fetch("refresh_token"),
          expires_at: Time.current + body.fetch("expires_in").to_i.seconds
        }
      end

      def body
        client_result[:body]
      end

      def missing_code_error
        { success: false, errors: [ "Authorization code is required" ] }
      end
    end
  end
end
