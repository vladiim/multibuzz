# frozen_string_literal: true

module AdPlatforms
  module Google
    class OauthUrl
      def initialize(state:)
        raise ArgumentError, "State parameter is required" if state.blank?

        @state = state
      end

      def call
        "#{AUTHORIZATION_URI}?#{URI.encode_www_form(params)}"
      end

      private

      attr_reader :state

      def params
        {
          client_id: Google.credentials.fetch(:client_id),
          redirect_uri: Google.redirect_uri,
          response_type: RESPONSE_TYPE_CODE,
          scope: SCOPE,
          access_type: ACCESS_TYPE_OFFLINE,
          prompt: PROMPT_CONSENT,
          state: state
        }
      end
    end
  end
end
