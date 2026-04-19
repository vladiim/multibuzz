# frozen_string_literal: true

module AdPlatforms
  module Google
    class AcceptConnectionService
      def initialize(account:, params:, tokens:)
        @account = account
        @params = params
        @tokens = tokens
      end

      def call
        return at_limit_outcome unless account.can_add_ad_platform_connection?
        return duplicate_outcome if duplicate?

        persist_and_enqueue
        success_outcome
      end

      private

      attr_reader :account, :params, :tokens

      def persist_and_enqueue
        connection.save!
        AdPlatforms::SpendSyncJob.perform_later(connection.id, date_range: backfill_range)
      end

      def connection
        @connection ||= account.ad_platform_connections.build(connection_attributes)
      end

      def connection_attributes
        {
          platform: :google_ads,
          platform_account_id: params[:customer_id],
          platform_account_name: params[:customer_name],
          currency: params[:currency],
          access_token: tokens["access_token"],
          refresh_token: tokens["refresh_token"],
          token_expires_at: Time.parse(tokens["expires_at"]),
          status: :connected,
          settings: { "login_customer_id" => params[:login_customer_id].presence }.compact
        }
      end

      def duplicate?
        account.ad_platform_connections.exists?(
          platform: :google_ads,
          platform_account_id: params[:customer_id]
        )
      end

      def backfill_range
        ConnectionSyncService::BACKFILL_DAYS.days.ago.to_date..Date.current
      end

      def success_outcome
        { notice: "Google Ads account connected.", clear_session: true }
      end

      def at_limit_outcome
        { alert: account.ad_platform_at_limit_alert, clear_session: true }
      end

      def duplicate_outcome
        { alert: "This account is already connected.", clear_session: false }
      end
    end
  end
end
