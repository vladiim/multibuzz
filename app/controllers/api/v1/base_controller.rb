# frozen_string_literal: true

module Api
  module V1
    class BaseController < ActionController::API
      before_action :authenticate_api_key
      rescue_from StandardError, with: :handle_unexpected_error
      rescue_from ActionController::ParameterMissing, with: :handle_parameter_missing
      # Rate limiting disabled for MVP - usage tracked via Billing::UsageCounter
      # Re-enable with smarter limits when billing tiers are implemented
      # before_action :check_rate_limit
      # after_action :set_rate_limit_headers

      private

      attr_reader :current_account, :current_api_key

      def authenticate_api_key
        auth_result = ApiKeys::AuthenticationService.new(authorization_header).call

        unless auth_result[:success]
          log_auth_failure(auth_result)
          return render_unauthorized(auth_result[:error])
        end

        @current_account = auth_result[:account]
        @current_api_key = auth_result[:api_key]

        render_account_suspended unless current_account.active?
      end

      def authorization_header
        request.headers["Authorization"]
      end

      def render_unauthorized(error)
        render json: { error: error }, status: :unauthorized
      end

      def render_account_suspended
        log_request_failure(
          error_type: :auth_account_suspended,
          error_message: "Account suspended",
          http_status: 401
        )
        render json: { error: "Account suspended" }, status: :unauthorized
      end

      def render_bad_request(error)
        render json: { error: error }, status: :bad_request
      end

      def render_unprocessable(data)
        render json: data, status: :unprocessable_entity
      end

      def log_auth_failure(auth_result)
        log_request_failure(
          error_type: "auth_#{auth_result[:error_code]}",
          error_message: auth_result[:error],
          http_status: 401
        )
      end

      def handle_parameter_missing(exception)
        render json: { error: exception.message }, status: :bad_request
      end

      def handle_unexpected_error(exception)
        Rails.error.report(exception, handled: true, context: {
          path: request.path,
          method: request.method,
          account_id: current_account&.id,
          request_id: request.request_id
        })
        render json: { error: "Internal server error" }, status: :internal_server_error
      end

      def log_request_failure(error_type:, error_message:, http_status:, error_details: {})
        ApiRequestLogs::RecordService.new(
          request: request,
          account: current_account,
          error_type: error_type,
          error_message: error_message,
          http_status: http_status,
          error_details: error_details
        ).call
      end
    end
  end
end
