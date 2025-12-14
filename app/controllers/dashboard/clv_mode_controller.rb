module Dashboard
  class ClvModeController < BaseController
    VALID_CLV_MODES = %w[transactions clv].freeze
    DEFAULT_CLV_MODE = "transactions"

    def update
      session[:clv_mode] = valid_mode

      respond_to do |format|
        format.html { redirect_back(fallback_location: dashboard_conversions_path) }
        format.turbo_stream { head :ok }
      end
    end

    private

    def valid_mode
      params[:mode].presence_in(VALID_CLV_MODES) || DEFAULT_CLV_MODE
    end
  end
end
