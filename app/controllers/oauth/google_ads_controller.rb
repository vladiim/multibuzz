# frozen_string_literal: true

module Oauth
  class GoogleAdsController < ApplicationController
    skip_marketing_analytics
    before_action :require_login
    before_action :require_paid_plan, only: :connect
    before_action :require_connection_slot, only: :connect
    before_action :require_oauth_account, only: [ :callback, :select_account, :create_connection ]
    before_action :require_session_tokens, only: [ :select_account, :create_connection ]

    def connect
      session[:oauth_state] = state
      session[:oauth_account_id] = current_account.id
      redirect_to oauth_url, allow_other_host: true
    end

    def callback
      return redirect_with_state_error unless valid_state?
      return redirect_with_error(exchange_result) unless exchange_result[:success]

      reconnecting? ? complete_reconnect : begin_account_selection
    end

    def select_account
      if customer_list_result[:success]
        @customers = customer_list_result[:customers]
      else
        @customers = []
        @error = customer_list_result[:errors]&.first
      end

      @known_metadata_keys = AdPlatforms::KnownMetadata.keys_for(oauth_account)
      @known_metadata_values = AdPlatforms::KnownMetadata.values_by_key_for(oauth_account)
    end

    def create_connection
      outcome = AdPlatforms::Google::AcceptConnectionService.new(
        account: oauth_account, params: params, tokens: session_tokens, metadata: extracted_metadata
      ).call
      clear_oauth_session! if outcome[:clear_session]
      redirect_to account_integrations_path, **outcome.except(:clear_session)
    end

    def reconnect
      session[:oauth_state] = state
      session[:oauth_account_id] = current_account.id
      session[:oauth_reconnect_id] = connection.prefix_id
      redirect_to oauth_url, allow_other_host: true
    end

    def disconnect
      connection.mark_disconnected!
      redirect_to account_integrations_path, notice: "Google Ads disconnected."
    end

    private

    # --- OAuth connect ---

    def state
      @state ||= SecureRandom.urlsafe_base64(32)
    end

    def oauth_url
      AdPlatforms::Google::OauthUrl.new(state: state).call
    end

    def valid_state?
      params[:state].present? && params[:state] == session[:oauth_state]
    end

    def exchange_result
      @exchange_result ||= AdPlatforms::Google::TokenExchanger.new(code: params[:code]).call
    end

    def reconnecting?
      session[:oauth_reconnect_id].present?
    end

    def begin_account_selection
      store_tokens_in_session
      session.delete(:oauth_state)
      redirect_to oauth_google_ads_select_account_path
    end

    def complete_reconnect
      reconnect_connection.update!(
        access_token: exchange_result[:access_token],
        refresh_token: exchange_result[:refresh_token],
        token_expires_at: exchange_result[:expires_at],
        status: :connected,
        last_sync_error: nil
      )
      clear_oauth_session!
      redirect_to account_integrations_path, notice: "Google Ads re-authenticated."
    end

    def reconnect_connection
      @reconnect_connection ||= oauth_account.ad_platform_connections.find_by_prefix_id!(session[:oauth_reconnect_id])
    end

    def store_tokens_in_session
      session[:google_ads_tokens] = {
        "access_token" => exchange_result[:access_token],
        "refresh_token" => exchange_result[:refresh_token],
        "expires_at" => exchange_result[:expires_at].iso8601
      }
    end

    # --- Account selection ---

    def session_tokens
      session[:google_ads_tokens]
    end

    def access_token
      session_tokens&.dig("access_token")
    end

    def customer_list_result
      @customer_list_result ||= AdPlatforms::Google::ListCustomers.new(
        access_token: access_token
      ).call
    end

    # --- Connect-time metadata ---

    def extracted_metadata
      AdPlatforms::ConnectMetadataExtractor.call(params)
    end

    # --- Disconnect ---

    def connection
      @connection ||= current_account.ad_platform_connections.find_by_prefix_id!(params[:id])
    end

    # --- Session pinning ---

    def oauth_account
      @oauth_account ||= current_user.active_accounts.find(session[:oauth_account_id])
    end

    def clear_oauth_session!
      session.delete(:oauth_account_id)
      session.delete(:google_ads_tokens)
      session.delete(:oauth_state)
      session.delete(:oauth_reconnect_id)
    end

    # --- Guards ---

    def require_paid_plan
      redirect_with_limit_error unless current_account.can_connect_ad_platform?
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

      redirect_to account_integrations_path, alert: "Please connect Google Ads first."
    end

    # --- Error redirects ---

    def redirect_with_limit_error
      redirect_to account_integrations_path, alert: "Ad platform integrations require a paid plan. Please upgrade to connect."
    end

    def redirect_with_state_error
      redirect_to account_integrations_path, alert: "OAuth verification failed. Please try again."
    end

    def redirect_with_error(result)
      redirect_to account_integrations_path, alert: result[:errors]&.first || "Failed to connect Google Ads."
    end
  end
end
