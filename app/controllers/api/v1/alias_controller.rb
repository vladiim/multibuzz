module Api
  module V1
    class AliasController < BaseController
      def create
        alias_result[:success] ? render_success : render_unprocessable(errors: alias_result[:errors])
      end

      private

      def alias_result
        @alias_result ||= Identities::AliasService.new(
          current_account,
          alias_params,
          is_test: current_api_key.test?
        ).call
      end

      def alias_params
        @alias_params ||= params.permit(:visitor_id, :user_id)
      end

      def render_success
        render json: { success: true }, status: :ok
      end
    end
  end
end
