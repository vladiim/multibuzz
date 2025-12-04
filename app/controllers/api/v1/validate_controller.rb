module Api
  module V1
    class ValidateController < BaseController
      def show
        render json: {
          valid: true,
          account: {
            id: current_account.prefix_id,
            name: current_account.name
          }
        }
      end
    end
  end
end
