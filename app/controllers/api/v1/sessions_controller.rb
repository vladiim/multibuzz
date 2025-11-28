module Api
  module V1
    class SessionsController < BaseController
      def create
        return render_bad_request("Missing 'session' parameter") unless session_param_present?

        creation_result[:success] ? render_accepted : render_unprocessable(errors: creation_result[:errors])
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
          :started_at
        )
      end

      def render_accepted
        render json: accepted_response, status: :accepted
      end

      def accepted_response
        {
          status: "accepted",
          visitor_id: creation_result[:visitor_id],
          session_id: creation_result[:session_id],
          channel: creation_result[:channel]
        }
      end
    end
  end
end
