# frozen_string_literal: true

module AdPlatforms
  module Google
    class ConnectionSyncService
      INCREMENTAL_LOOKBACK_DAYS = 3
      BACKFILL_DAYS = 90

      def initialize(connection, date_range: nil)
        @connection = connection
        @date_range_override = date_range
      end

      def call
        ensure_fresh_token
        sync_result[:success] ? complete_sync : fail_sync
      rescue TokenRefreshError => e
        fail_sync(e.message)
      end

      private

      attr_reader :connection, :date_range_override

      def ensure_fresh_token
        return unless connection.token_expired?
        raise TokenRefreshError, token_refresh[:errors]&.first unless token_refresh[:success]

        connection.update!(access_token: token_refresh[:access_token], token_expires_at: token_refresh[:expires_at])
      end

      def complete_sync
        sync_run.update!(status: :completed, records_synced: sync_result[:records_synced], completed_at: Time.current)
        connection.mark_connected!
      end

      def fail_sync(message = sync_result[:errors]&.first)
        sync_run.update!(status: :failed, error_message: message, completed_at: Time.current)
        connection.mark_error!(message)
      end

      def sync_result
        @sync_result ||= SpendSyncService.new(connection, date_range: date_range).call
      end

      def sync_run
        @sync_run ||= connection.ad_spend_sync_runs.create!(sync_date: Date.current, status: :running, started_at: Time.current)
      end

      def token_refresh
        @token_refresh ||= TokenRefresher.new(connection).call
      end

      def date_range
        date_range_override || (INCREMENTAL_LOOKBACK_DAYS.days.ago.to_date..Date.current)
      end

      TokenRefreshError = Class.new(StandardError)
    end
  end
end
