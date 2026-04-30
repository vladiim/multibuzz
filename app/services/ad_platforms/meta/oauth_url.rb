# frozen_string_literal: true

module AdPlatforms
  module Meta
    class OauthUrl
      def initialize(state:, client_id:, redirect_uri:)
        raise ArgumentError, "State parameter is required" if state.blank?

        @state = state
        @client_id = client_id
        @redirect_uri = redirect_uri
      end

      def call
        "#{AUTHORIZATION_URI}?#{URI.encode_www_form(params)}"
      end

      private

      attr_reader :state, :client_id, :redirect_uri

      def params
        {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: RESPONSE_TYPE_CODE,
          scope: SCOPE,
          state: state
        }
      end
    end
  end
end
