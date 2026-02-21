# frozen_string_literal: true

module Dashboard
  class ClvModeController < BaseController
    VALID_CLV_MODES = %w[transactions clv].freeze
    DEFAULT_CLV_MODE = "transactions"

    def update
      session[:clv_mode] = valid_mode

      redirect_to dashboard_path
    end

    private

    def valid_mode
      params[:mode].presence_in(VALID_CLV_MODES) || DEFAULT_CLV_MODE
    end
  end
end
