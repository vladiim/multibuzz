# frozen_string_literal: true

module AdPlatforms
  module Meta
    # Refreshes a Meta long-lived access token by re-exchanging the current token
    # via the fb_exchange_token grant type. Meta rotates the value but the new
    # token is also long-lived (~60 days).
    #
    # Test posture: integration via VCR cassette in the OAuth controller flow
    # (Sub-phase 2.8). Not unit-tested in isolation — composition is shallow:
    # TokenClient (HTTP shell) → TokenExchanger (pure parser, already tested) →
    # connection.update!.
    class TokenRefresher
      def initialize(connection)
        @connection = connection
      end

      def call
        return token_result unless token_result[:success]

        connection.update!(
          access_token: token_result[:access_token],
          token_expires_at: token_result[:expires_at],
          status: :connected,
          last_sync_error: nil
        )
        token_result
      end

      private

      attr_reader :connection

      def token_result
        @token_result ||= TokenExchanger.new(body: response_body).call
      end

      def response_body
        @response_body ||= TokenClient.new(params: refresh_params).call
      end

      def refresh_params
        {
          grant_type: GRANT_FB_EXCHANGE,
          client_id: Meta.credentials.fetch(:app_id),
          client_secret: Meta.credentials.fetch(:app_secret),
          fb_exchange_token: connection.access_token
        }
      end
    end
  end
end
