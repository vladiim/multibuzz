# frozen_string_literal: true

module Accounts
  class IntegrationsController < BaseController
    include RequireAdmin

    def show
      @connections = current_account.ad_platform_connections.order(created_at: :desc)
      @can_connect = current_account.can_connect_ad_platform?
    end
  end
end
