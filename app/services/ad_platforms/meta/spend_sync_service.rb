# frozen_string_literal: true

module AdPlatforms
  module Meta
    # Pulls /insights for the connection's ad account over the given date range,
    # parses each row, upserts as AdSpendRecord. Increments the account's billing
    # usage meter by the number of rows synced.
    #
    # Test posture: VCR cassettes recorded against a real Meta account in
    # Phase 5 (pet-resort end-to-end). The pure RowParser + CampaignChannelMapper
    # already cover the row-level transformation logic.
    class SpendSyncService
      def initialize(connection, date_range:, channel_overrides: nil)
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
        rows = []
        body = client.get(insights_uri, query: insights_query)

        loop do
          rows.concat(Array(body[FIELD_DATA]))
          next_url = body.dig(FIELD_PAGING, FIELD_NEXT)
          break unless next_url

          body = client.get(URI(next_url))
        end

        rows
      end

      def client
        @client ||= ApiClient.new(access_token: connection.access_token)
      end

      def insights_uri
        URI("#{GRAPH_BASE_URL}/#{API_VERSION}/#{connection.platform_account_id}/insights")
      end

      def insights_query
        {
          level: INSIGHTS_LEVEL,
          fields: INSIGHTS_FIELDS,
          time_range: { since: date_range.first.to_s, until: date_range.last.to_s }.to_json,
          time_increment: INSIGHTS_TIME_INCREMENT_DAILY
        }
      end

      def upsert_records
        AdSpendRecord.upsert_all(records, unique_by: :idx_spend_unique)
      end

      def meter_usage
        connection.account.increment_usage!(records.size)
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
