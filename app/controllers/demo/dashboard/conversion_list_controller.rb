# frozen_string_literal: true

module Demo
  module Dashboard
    class ConversionListController < ApplicationController
      def index
        @demo_mode = true
        result = service.call
        @conversions = result[:conversions]
        @total_count = result[:total_count]
      end

      def show
        @demo_mode = true
        @conversion = service.find(params[:id])

        redirect_to demo_dashboard_conversion_list_path unless @conversion
      end

      private

      def service = @service ||= ::Dashboard::Dummy::ConversionListDataService.new
    end
  end
end
