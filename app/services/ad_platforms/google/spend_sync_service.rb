# frozen_string_literal: true

module AdPlatforms
  module Google
    class SpendSyncService
      def initialize(connection, date_range:, channel_overrides: {})
        @connection = connection
        @date_range = date_range
        @channel_overrides = channel_overrides
      end

      def call
        return empty_result if records.empty?

        upsert_records
        meter_usage
        success_result
      end

      private

      attr_reader :connection, :date_range, :channel_overrides

      def records
        @records ||= raw_rows.map { |row| RowParser.call(row, connection: connection, channel_overrides: channel_overrides) }
      end

      def raw_rows
        standard_results + pmax_results
      end

      def standard_results
        client.search(formatted_query(STANDARD_SPEND_QUERY)).fetch(FIELD_RESULTS, [])
      end

      def pmax_results
        client.search(formatted_query(PMAX_SPEND_QUERY)).fetch(FIELD_RESULTS, [])
      end

      def upsert_records
        AdSpendRecord.upsert_all(records, unique_by: :idx_spend_unique)
      end

      def meter_usage
        connection.account.increment_usage!(records.size)
      end

      def client
        @client ||= ApiClient.new(
          access_token: connection.access_token,
          customer_id: connection.platform_account_id,
          login_customer_id: connection.settings["login_customer_id"]
        )
      end

      def formatted_query(template)
        format(template, date_range.first, date_range.last)
      end

      def success_result
        { success: true, records_synced: records.size }
      end

      def empty_result
        { success: true, records_synced: 0 }
      end
    end
  end
end
