# frozen_string_literal: true

module Dashboard
  class ViewModeController < BaseController
    def update
      session[:view_mode] = valid_mode
      persist_live_mode

      respond_to do |format|
        format.html { redirect_back(fallback_location: dashboard_path) }
        format.turbo_stream { head :ok }
      end
    end

    private

    def valid_mode
      params[:mode].presence_in(VALID_VIEW_MODES) || DEFAULT_VIEW_MODE
    end

    def persist_live_mode
      current_account.update!(live_mode_enabled: valid_mode == DEFAULT_VIEW_MODE)
    end
  end
end
