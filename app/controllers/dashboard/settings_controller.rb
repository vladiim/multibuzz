module Dashboard
  class SettingsController < BaseController
    def show
      @api_keys = current_account.api_keys.order(created_at: :desc)
      @tab = params[:tab].presence_in(%w[api_keys team]) || "api_keys"
    end
  end
end
