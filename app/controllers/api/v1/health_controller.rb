module Api
  module V1
    class HealthController < ActionController::API
      API_VERSION = "1.0.0"

      def show
        render json: {
          status: "ok",
          version: API_VERSION
        }
      end
    end
  end
end
