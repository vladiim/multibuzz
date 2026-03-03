# frozen_string_literal: true

module Accounts
  class IntegrationsController < BaseController
    include RequireAdmin

    def show
      @connections = current_account.ad_platform_connections.order(created_at: :desc)
      @can_connect = current_account.can_connect_ad_platform?
    end

    def refresh
      AdPlatforms::SpendSyncJob.perform_later(connection.id)
      redirect_to account_integrations_path, notice: "Sync started. Data will update shortly."
    end

    private

    def connection
      @connection ||= current_account.ad_platform_connections.find_by_prefix_id!(params[:id])
    end
  end
end
