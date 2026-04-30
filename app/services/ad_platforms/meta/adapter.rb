# frozen_string_literal: true

module AdPlatforms
  module Meta
    class Adapter < BaseAdapter
      def fetch_spend(date_range:)
        SpendSyncService.new(connection, date_range: date_range).call
      end

      def refresh_token!
        TokenRefresher.new(connection).call
      end

      def validate_connection
        return refresh_token! if token_expired?

        { success: true }
      end

      private

      def token_expired?
        connection.token_expires_at.blank? || connection.token_expires_at < Time.current
      end
    end
  end
end
