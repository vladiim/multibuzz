# frozen_string_literal: true

module Api
  module V1
    class DataController < BaseController
      rescue_from Date::Error, with: :render_bad_date_format

      def conversions
        render json: query_result(DataDownloads::ConversionsQueryService)
      end

      def funnel
        render json: query_result(DataDownloads::FunnelQueryService)
      end

      def spend
        render json: query_result(DataDownloads::SpendQueryService)
      end

      private

      def render_bad_date_format
        render json: { error: "Invalid date format. Use YYYY-MM-DD." }, status: :bad_request
      end

      def query_result(service_class)
        service_class.new(current_account, query_params).call
      end

      def query_params
        {
          date_range: date_range_param,
          channels: channels_param,
          funnel: params[:funnel].presence,
          page: params[:page],
          per_page: params[:per_page],
          test_mode: current_api_key.test?
        }
      end

      def date_range_param
        return params[:date_range] if params[:date_range].present?
        return { start_date: params[:start_date], end_date: params[:end_date] } if custom_date_range?

        nil
      end

      def custom_date_range?
        params[:start_date].present? && params[:end_date].present?
      end

      def channels_param
        return nil if params[:channels].blank?

        Array(params[:channels]).map(&:to_s)
      end
    end
  end
end
