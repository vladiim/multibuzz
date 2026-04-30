# frozen_string_literal: true

module AdPlatforms
  module Meta
    # Creates an AdPlatformConnection for the selected Meta ad account once OAuth
    # has produced a long-lived token. No HTTP — tokens are passed in by the
    # controller after the exchange chain has completed.
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
        AdPlatforms::SpendSyncJob.perform_later(connection.id)
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
          platform: :meta_ads,
          platform_account_id: params[:ad_account_id],
          platform_account_name: params[:ad_account_name],
          currency: params[:currency],
          access_token: tokens[:access_token],
          token_expires_at: tokens[:expires_at],
          status: :connected,
          settings: { "timezone_name" => params[:timezone_name] }.compact,
          metadata: AdPlatforms::MetadataNormalizer.call(metadata)
        }
      end

      def duplicate?
        account.ad_platform_connections.exists?(
          platform: :meta_ads,
          platform_account_id: params[:ad_account_id]
        )
      end

      def success_outcome
        { notice: "Meta Ads account connected.", clear_session: true }
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
