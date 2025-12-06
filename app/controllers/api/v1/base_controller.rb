module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_key
      # Rate limiting disabled for MVP - usage tracked via Billing::UsageCounter
      # Re-enable with smarter limits when billing tiers are implemented
      # before_action :check_rate_limit
      # after_action :set_rate_limit_headers

      private

      attr_reader :current_account, :current_api_key

      def authenticate_api_key
        authentication_result = ApiKeys::AuthenticationService.new(authorization_header).call

        return render_unauthorized(authentication_result[:error]) unless authentication_result[:success]

        @current_account = authentication_result[:account]
        @current_api_key = authentication_result[:api_key]

        return render_unauthorized("Account suspended") unless current_account.active?
      end

      def authorization_header
        request.headers["Authorization"]
      end

      def render_unauthorized(error)
        render json: { error: error }, status: :unauthorized
      end

      def render_bad_request(error)
        render json: { error: error }, status: :bad_request
      end

      def render_unprocessable(data)
        render json: data, status: :unprocessable_entity
      end
    end
  end
end
