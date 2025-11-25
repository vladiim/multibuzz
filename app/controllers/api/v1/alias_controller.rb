module Api
  module V1
    class AliasController < BaseController
      def create
        return render_unprocessable(result) unless result[:success]

        render json: { success: true }, status: :ok
      end

      private

      def result
        @result ||= Visitors::AliasService
          .new(current_account, alias_params)
          .call
      end

      def alias_params
        params.permit(:visitor_id, :user_id)
      end
    end
  end
end
