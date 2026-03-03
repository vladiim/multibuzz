# frozen_string_literal: true

module AdPlatforms
  module Google
    class TokenRefresher
      def initialize(connection)
        @connection = connection
      end

      def call
        return missing_token_error if connection.refresh_token.blank?
        return client_result unless client_result[:success]

        build_tokens
      end

      private

      attr_reader :connection

      def client_result
        @client_result ||= TokenClient.new(
          grant_type: GRANT_REFRESH_TOKEN,
          refresh_token: connection.refresh_token
        ).call
      end

      def build_tokens
        {
          success: true,
          access_token: body.fetch("access_token"),
          expires_at: Time.current + body.fetch("expires_in").to_i.seconds
        }
      end

      def body
        client_result[:body]
      end

      def missing_token_error
        { success: false, errors: [ "No refresh token available" ] }
      end
    end
  end
end
