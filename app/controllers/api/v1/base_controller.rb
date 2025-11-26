module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_key
      before_action :check_rate_limit
      after_action :set_rate_limit_headers

      private

      attr_reader :current_account, :current_api_key

      def authenticate_api_key
        authentication_result = ApiKeys::AuthenticationService.new(authorization_header).call

        return render_unauthorized(authentication_result[:error]) unless authentication_result[:success]

        @current_account = authentication_result[:account]
        @current_api_key = authentication_result[:api_key]

        return render_unauthorized("Account suspended") unless current_account.active?
      end

      def check_rate_limit
        return render_rate_limited unless rate_limit_result[:allowed]
      end

      def rate_limit_result
        @rate_limit_result ||= ApiKeys::RateLimiterService.new(current_account).call
      end

      def set_rate_limit_headers
        return unless rate_limit_result

        response.set_header("X-RateLimit-Limit", "1000")
        response.set_header("X-RateLimit-Remaining", rate_limit_result[:remaining].to_s)
        response.set_header("X-RateLimit-Reset", rate_limit_result[:reset_at].to_i.to_s)
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

      def render_rate_limited
        render json: {
          error: rate_limit_result[:error],
          retry_after: rate_limit_result[:retry_after]
        }, status: :too_many_requests
      end
    end
  end
end
