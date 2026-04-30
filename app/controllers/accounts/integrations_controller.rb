# frozen_string_literal: true

module Accounts
  class IntegrationsController < BaseController
    include RequireAdmin
    skip_marketing_analytics

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

    def meta_ads
      return redirect_to(account_integrations_path, alert: "Meta Ads integration is not enabled for your account yet.") unless current_account.feature_enabled?(FeatureFlags::META_ADS_INTEGRATION)

      @connections = current_account.ad_platform_connections.where(platform: :meta_ads).where.not(status: :disconnected).order(created_at: :desc)
    end

    def meta_ads_account
      return redirect_to(account_integrations_path, alert: "Meta Ads integration is not enabled for your account yet.") unless current_account.feature_enabled?(FeatureFlags::META_ADS_INTEGRATION)

      @connection = connection
    end

    def refresh
      return dismiss_verification if params[:dismiss_verification]

      AdPlatforms::SpendSyncJob.perform_later(connection.id)
      redirect_back fallback_location: account_integrations_path
    end

    def update_metadata
      connection.update!(metadata: AdPlatforms::MetadataNormalizer.call(metadata_pair))
      AdPlatforms::MetadataBackfillJob.perform_later(connection.id)
      redirect_to detail_path_for(connection), notice: "Metadata updated. Backfill in progress."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to detail_path_for(connection), alert: e.message
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

    def detail_path_for(connection)
      case connection.platform.to_sym
      when :google_ads then google_ads_detail_account_integrations_path(connection)
      when :meta_ads then meta_ads_detail_account_integrations_path(connection)
      end
    end

    def metadata_pair
      @metadata_pair ||= metadata_key.empty? ? {} : { metadata_key => metadata_value }
    end

    def metadata_key
      @metadata_key ||= params[:metadata_key].to_s
    end

    def metadata_value
      @metadata_value ||= params[:metadata_value].to_s
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
