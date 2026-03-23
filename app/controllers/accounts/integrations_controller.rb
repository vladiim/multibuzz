# frozen_string_literal: true

module Accounts
  class IntegrationsController < BaseController
    include RequireAdmin

    def show
      @connections = current_account.ad_platform_connections.order(created_at: :desc)
      @notified_platforms = IntegrationRequestSubmission
        .where(email: current_user.email)
        .pluck(Arel.sql("data->>'platform_name'"))
    end

    def google_ads
      @connections = current_account.ad_platform_connections.where(platform: :google_ads).where.not(status: :disconnected).order(created_at: :desc)
    end

    def google_ads_account
      @connection = connection
    end

    def refresh
      return dismiss_verification if params[:dismiss_verification]

      AdPlatforms::SpendSyncJob.perform_later(connection.id)
      redirect_back fallback_location: account_integrations_path
    end

    def notify
      result = create_service.call
      redirect_to account_integrations_path, notice: result_notice(result)
    end

    def request_integration
      result = create_service.call
      redirect_to account_integrations_path, notice: result_notice(result)
    end

    private

    def dismiss_verification
      connection.update!(settings: connection.settings.merge(AdPlatformConnection::SETTING_VERIFICATION_DISMISSED => true))
      redirect_to account_integrations_path
    end

    def connection
      @connection ||= current_account.ad_platform_connections.find_by_prefix_id!(params[:id])
    end

    def create_service
      IntegrationRequest::CreateService.new(
        user: current_user, account: current_account,
        params: params, request: request
      )
    end

    def result_notice(result)
      return result[:errors].first unless result[:success]

      platform = result[:submission].platform_name
      "We'll notify you when #{platform} is available."
    end
  end
end
