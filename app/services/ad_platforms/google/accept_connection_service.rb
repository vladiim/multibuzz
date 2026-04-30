# frozen_string_literal: true

module AdPlatforms
  module Google
    class AcceptConnectionService
      def initialize(account:, params:, tokens:, metadata: {})
        @account = account
        @params = params
        @tokens = tokens
        @metadata = metadata
      end

      def call
        return at_limit_outcome unless account.can_add_ad_platform_connection?
        return duplicate_outcome if duplicate?

        persist_and_enqueue
        track_connection
        success_outcome
      end

      private

      attr_reader :account, :params, :tokens, :metadata

      def persist_and_enqueue
        connection.save!
        AdPlatforms::SpendSyncJob.perform_later(connection.id, date_range: backfill_range)
      end

      def track_connection
        Lifecycle::Tracker.track(
          "feature_ad_platform_connected",
          account,
          platform: connection.platform,
          connections_used: account.ad_platform_connections.count,
          connection_limit: account.ad_platform_connection_limit
        )
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
          settings: { "login_customer_id" => params[:login_customer_id].presence }.compact,
          metadata: AdPlatforms::MetadataNormalizer.call(metadata)
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
        { notice: "Google Ads account connected. Connect more from this list, or click Done when you're finished.", clear_session: false }
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
