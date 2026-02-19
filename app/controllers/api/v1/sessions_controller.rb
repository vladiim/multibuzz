module Api
  module V1
    class SessionsController < BaseController
      def create
        return render_bad_request("Missing 'session' parameter") unless session_param_present?

        creation_result[:success] ? render_accepted : render_failure
      end

      private

      def session_param_present?
        params.key?(:session)
      end

      def creation_result
        @creation_result ||= Sessions::CreationService.new(
          current_account,
          session_params,
          is_test: current_api_key.test?
        ).call
      end

      def session_params
        @session_params ||= params.require(:session).permit(
          :visitor_id,
          :session_id,
          :url,
          :referrer,
          :started_at,
          :device_fingerprint,
          :user_agent
        )
      end

      def render_accepted
        render json: accepted_response, status: :accepted
      end

      def render_failure
        log_session_failure
        render_unprocessable(creation_result)
      end

      def accepted_response
        {
          status: "accepted",
          visitor_id: creation_result[:visitor_id],
          session_id: creation_result[:session_id],
          channel: creation_result[:channel]
        }
      end

      def log_session_failure
        log_request_failure(
          error_type: :validation_missing_param,
          error_message: creation_result[:errors].join(", "),
          http_status: 422,
          error_details: session_params.to_h
        )
      end
    end
  end
end
