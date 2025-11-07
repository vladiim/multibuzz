module Api
  module V1
    class HealthController < ActionController::API
      def show
        render json: {
          status: "ok",
          timestamp: Time.current.iso8601,
          checks: {
            database: database_connected?
          }
        }
      end

      private

      def database_connected?
        ActiveRecord::Base.connection.active?
      rescue StandardError
        false
      end
    end
  end
end
