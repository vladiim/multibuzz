# frozen_string_literal: true

module Demo
  module Dashboard
    class ClvModeController < ApplicationController
      VALID_CLV_MODES = %w[transactions clv].freeze
      DEFAULT_CLV_MODE = "transactions"

      def update
        session[:demo_clv_mode] = valid_mode

        redirect_to demo_dashboard_path
      end

      private

      def valid_mode
        params[:mode].presence_in(VALID_CLV_MODES) || DEFAULT_CLV_MODE
      end
    end
  end
end
