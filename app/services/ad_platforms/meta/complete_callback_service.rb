# frozen_string_literal: true

module AdPlatforms
  module Meta
    # Runs the full Meta OAuth callback chain in one place: code → short-lived
    # token → long-lived token. Returns the final long-lived token result.
    # Keeps the controller's #callback action a thin delegator.
    class CompleteCallbackService
      def initialize(code:)
        @code = code
      end

      def call
        return missing_code_result if code.blank?
        return short_lived_result unless short_lived_result[:success]

        long_lived_result
      end

      private

      attr_reader :code

      def short_lived_result
        @short_lived_result ||= TokenExchanger.new(body: TokenClient.new(params: short_lived_params).call).call
      end

      def long_lived_result
        @long_lived_result ||= TokenExchanger.new(body: TokenClient.new(params: long_lived_params).call).call
      end

      def short_lived_params
        {
          client_id: Meta.credentials.fetch(:app_id),
          client_secret: Meta.credentials.fetch(:app_secret),
          redirect_uri: Meta.redirect_uri,
          code: code
        }
      end

      def long_lived_params
        {
          grant_type: GRANT_FB_EXCHANGE,
          client_id: Meta.credentials.fetch(:app_id),
          client_secret: Meta.credentials.fetch(:app_secret),
          fb_exchange_token: short_lived_result[:access_token]
        }
      end

      def missing_code_result
        { success: false, errors: [ "Authorization code is required" ] }
      end
    end
  end
end
