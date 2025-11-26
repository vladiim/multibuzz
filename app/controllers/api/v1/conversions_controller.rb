# frozen_string_literal: true

module Api
  module V1
    class ConversionsController < BaseController
      def create
        return render_unprocessable(tracking_result) unless tracking_result[:success]

        render json: Conversions::ResponseBuilder.new(tracking_result).call, status: :created
      end

      private

      def tracking_result
        @tracking_result ||= Conversions::TrackingService.new(current_account, conversion_params).call
      end

      def conversion_params
        params.require(:conversion).permit(:event_id, :visitor_id, :conversion_type, :revenue, properties: {})
      end
    end
  end
end
