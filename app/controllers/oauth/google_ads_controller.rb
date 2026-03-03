# frozen_string_literal: true

module Oauth
  class GoogleAdsController < ApplicationController
    before_action :require_login
    before_action :require_oauth_account, only: [ :callback, :select_account, :create_connection ]
    before_action :require_session_tokens, only: [ :select_account, :create_connection ]

    def connect
      return redirect_with_limit_error unless current_account.can_connect_ad_platform?

      session[:oauth_state] = state
      session[:oauth_account_id] = current_account.id
      redirect_to oauth_url, allow_other_host: true
    end

    def callback
      return redirect_with_state_error unless valid_state?
      return redirect_with_error(exchange_result) unless exchange_result[:success]

      store_tokens_in_session
      session.delete(:oauth_state)
      redirect_to oauth_google_ads_select_account_path
    end

    def select_account
      @customers = customer_list_result[:customers] if customer_list_result[:success]
      @customers ||= []
    end

    def create_connection
      return redirect_to(account_path, alert: "This account is already connected.") if duplicate_connection?

      build_connection.save!
      clear_oauth_session!
      redirect_to account_path, notice: "Google Ads account connected."
    end

    def disconnect
      connection.mark_disconnected!
      redirect_to account_path, notice: "Google Ads disconnected."
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

    def store_tokens_in_session
      session[:google_ads_tokens] = {
        access_token: exchange_result[:access_token],
        refresh_token: exchange_result[:refresh_token],
        expires_at: exchange_result[:expires_at].iso8601
      }
    end

    # --- Account selection ---

    def session_tokens
      session[:google_ads_tokens]
    end

    def customer_list_result
      @customer_list_result ||= AdPlatforms::Google::ListCustomers.new(
        access_token: session_tokens["access_token"]
      ).call
    end

    def duplicate_connection?
      oauth_account.ad_platform_connections.exists?(
        platform: :google_ads,
        platform_account_id: params[:customer_id]
      )
    end

    def build_connection
      oauth_account.ad_platform_connections.build(
        platform: :google_ads,
        platform_account_id: params[:customer_id],
        platform_account_name: params[:customer_name],
        currency: params[:currency],
        access_token: session_tokens["access_token"],
        refresh_token: session_tokens["refresh_token"],
        token_expires_at: Time.parse(session_tokens["expires_at"]),
        status: :connected
      )
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
    end

    # --- Guards ---

    def require_oauth_account
      return if session[:oauth_account_id].present? &&
                current_user.active_accounts.exists?(id: session[:oauth_account_id])

      redirect_to account_path, alert: "OAuth session expired. Please try connecting again."
    end

    def require_session_tokens
      return if session_tokens.present?

      redirect_to account_path, alert: "Please connect Google Ads first."
    end

    # --- Error redirects ---

    def redirect_with_limit_error
      redirect_to account_path, alert: "Your plan's ad platform connection limit has been reached. Please upgrade to connect more platforms."
    end

    def redirect_with_state_error
      redirect_to account_path, alert: "OAuth verification failed. Please try again."
    end

    def redirect_with_error(result)
      redirect_to account_path, alert: result[:errors]&.first || "Failed to connect Google Ads."
    end
  end
end
