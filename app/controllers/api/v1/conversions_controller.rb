# frozen_string_literal: true

module Api
  module V1
    class ConversionsController < BaseController
      def create
        unless tracking_result[:success]
          log_conversion_failure
          return render_unprocessable(tracking_result)
        end

        render json: Conversions::ResponseBuilder.new(tracking_result).call, status: :created
      end

      private

      def tracking_result
        @tracking_result ||= Conversions::TrackingService.new(
          current_account,
          conversion_params,
          is_test: current_api_key.test?
        ).call
      end

      def conversion_params
        params.require(:conversion).permit(
          :event_id, :visitor_id, :conversion_type, :revenue, :currency,
          :user_id, :is_acquisition, :inherit_acquisition, :ip, :user_agent,
          properties: {}
        )
      end

      def log_conversion_failure
        log_request_failure(
          error_type: conversion_error_type,
          error_message: tracking_result[:errors].join(", "),
          http_status: 422,
          error_details: conversion_params.to_h
        )
      end

      def conversion_error_type
        error_text = tracking_result[:errors].join(" ")
        return :visitor_not_found if error_text.include?("Visitor not found")
        return :validation_missing_param if error_text.include?("required")

        :validation_invalid_format
      end
    end
  end
end
