module Api
  module V1
    class IdentifyController < BaseController
      def create
        identification_result[:success] ? render_success : render_unprocessable(errors: identification_result[:errors])
      end

      private

      def identification_result
        @identification_result ||= Identities::IdentificationService.new(
          current_account,
          identify_params,
          is_test: current_api_key.test?
        ).call
      end

      def identify_params
        @identify_params ||= params.permit(:user_id, :visitor_id, traits: {})
      end

      def render_success
        render json: { success: true }, status: :ok
      end
    end
  end
end
