module Api
  module V1
    class IdentifyController < BaseController
      def create
        return render_unprocessable(result) unless result[:success]

        render json: { success: true }, status: :ok
      end

      private

      def result
        @result ||= Users::IdentificationService
          .new(current_account, identify_params)
          .call
      end

      def identify_params
        params.permit(:user_id, :visitor_id, traits: {})
      end
    end
  end
end
