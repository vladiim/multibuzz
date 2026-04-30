# frozen_string_literal: true

module Oauth
  class MetaAdsController < ApplicationController
    skip_marketing_analytics
    before_action :require_login
    before_action :require_feature_flag, only: [ :connect, :callback, :select_account, :create_connection, :done, :reconnect ]
    before_action :require_paid_plan, only: :connect
    before_action :require_connection_slot, only: :connect
    before_action :require_oauth_account, only: [ :callback, :select_account, :create_connection, :done ]
    before_action :require_session_tokens, only: [ :select_account, :create_connection ]

    def connect
      session[:oauth_state] = state
      session[:oauth_account_id] = current_account.id
      redirect_to oauth_url, allow_other_host: true
    end

    def callback
      return redirect_to(account_integrations_path, alert: "OAuth verification failed. Please try again.") unless valid_state?
      return redirect_to(account_integrations_path, alert: callback_result[:errors]&.first || "Failed to connect Meta Ads.") unless callback_result[:success]

      reconnecting? ? complete_reconnect : begin_account_selection
    end

    def select_account
      result = AdPlatforms::Meta::ListAdAccounts.new(access_token: session_access_token).call
      @ad_accounts = result[:accounts] || []
      @error = result[:errors]&.first unless result[:success]
      @known_metadata_keys = AdPlatforms::KnownMetadata.keys_for(oauth_account)
      @already_connected_ids = oauth_account.ad_platform_connections
        .where(platform: :meta_ads).pluck(:platform_account_id).to_set
    end

    def create_connection
      outcome = AdPlatforms::Meta::AcceptConnectionService.new(
        account: oauth_account, params: params, tokens: session_tokens, metadata: extracted_metadata
      ).call
      clear_oauth_session! if outcome[:clear_session]
      redirect_to outcome[:clear_session] ? meta_ads_account_integrations_path : oauth_meta_ads_select_account_path,
        **outcome.except(:clear_session)
    end

    def done
      clear_oauth_session!
      redirect_to meta_ads_account_integrations_path
    end

    def reconnect
      session[:oauth_state] = state
      session[:oauth_account_id] = current_account.id
      session[:oauth_reconnect_id] = connection.prefix_id
      redirect_to oauth_url, allow_other_host: true
    end

    def disconnect
      connection.mark_disconnected!
      redirect_to account_integrations_path, notice: "Meta Ads disconnected."
    end

    private

    def state
      @state ||= SecureRandom.urlsafe_base64(32)
    end

    def oauth_url
      AdPlatforms::Meta::OauthUrl.new(
        state: state,
        client_id: AdPlatforms::Meta.credentials.fetch(:app_id),
        redirect_uri: AdPlatforms::Meta.redirect_uri
      ).call
    end

    def valid_state?
      params[:state].present? && params[:state] == session[:oauth_state]
    end

    def callback_result
      @callback_result ||= AdPlatforms::Meta::CompleteCallbackService.new(code: params[:code]).call
    end

    def reconnecting?
      session[:oauth_reconnect_id].present?
    end

    def begin_account_selection
      session[:meta_ads_tokens] = { "access_token" => callback_result[:access_token], "expires_at" => callback_result[:expires_at].iso8601 }
      session.delete(:oauth_state)
      redirect_to oauth_meta_ads_select_account_path
    end

    def complete_reconnect
      reconnect_connection.update!(
        access_token: callback_result[:access_token],
        token_expires_at: callback_result[:expires_at],
        status: :connected,
        last_sync_error: nil
      )
      clear_oauth_session!
      redirect_to account_integrations_path, notice: "Meta Ads re-authenticated."
    end

    def reconnect_connection
      @reconnect_connection ||= oauth_account.ad_platform_connections.find_by_prefix_id!(session[:oauth_reconnect_id])
    end

    def session_tokens
      tokens = session[:meta_ads_tokens]
      tokens && { access_token: tokens["access_token"], expires_at: Time.parse(tokens["expires_at"]) }
    end

    def extracted_metadata
      AdPlatforms::ConnectMetadataExtractor.call(params)
    end

    def session_access_token
      session[:meta_ads_tokens]&.dig("access_token")
    end

    def connection
      @connection ||= current_account.ad_platform_connections.find_by_prefix_id!(params[:id])
    end

    def oauth_account
      @oauth_account ||= current_user.active_accounts.find(session[:oauth_account_id])
    end

    def clear_oauth_session!
      session.delete(:oauth_account_id)
      session.delete(:meta_ads_tokens)
      session.delete(:oauth_state)
      session.delete(:oauth_reconnect_id)
    end

    def require_feature_flag
      return if current_account.feature_enabled?(FeatureFlags::META_ADS_INTEGRATION)

      redirect_to account_integrations_path, alert: "Meta Ads integration is not enabled for your account yet."
    end

    def require_paid_plan
      return if current_account.can_connect_ad_platform?

      redirect_to account_integrations_path, alert: "Ad platform integrations require a paid plan. Please upgrade to connect."
    end

    def require_connection_slot
      return if current_account.can_add_ad_platform_connection?

      redirect_to account_integrations_path, alert: current_account.ad_platform_at_limit_alert
    end

    def require_oauth_account
      return if session[:oauth_account_id].present? &&
                current_user.active_accounts.exists?(id: session[:oauth_account_id])

      redirect_to account_integrations_path, alert: "OAuth session expired. Please try connecting again."
    end

    def require_session_tokens
      return if session_tokens.present?

      redirect_to account_integrations_path, alert: "Please connect Meta Ads first."
    end
  end
end
