module Api
  module V1
    class ValidateController < BaseController
      def show
        render json: {
          valid: true,
          account_id: current_account.id,
          environment: current_api_key.environment
        }
      end
    end
  end
end
