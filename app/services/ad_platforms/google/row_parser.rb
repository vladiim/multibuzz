# frozen_string_literal: true

module AdPlatforms
  module Google
    class RowParser
      def self.call(row, connection:, channel_overrides: {})
        new(row, connection: connection, channel_overrides: channel_overrides).call
      end

      def initialize(row, connection:, channel_overrides: {})
        @campaign = row.fetch(FIELD_CAMPAIGN)
        @segments = row.fetch(FIELD_SEGMENTS)
        @metrics = row.fetch(FIELD_METRICS)
        @currency = row.dig(FIELD_CUSTOMER, FIELD_CURRENCY_CODE) || connection.currency
        @connection = connection
        @channel_overrides = channel_overrides
      end

      def call
        connection_attrs.merge(dimension_attrs).merge(campaign_attrs).merge(metric_attrs).merge(metadata_attrs)
      end

      private

      attr_reader :campaign, :segments, :metrics, :currency, :connection, :channel_overrides

      def connection_attrs
        { account_id: connection.account_id, ad_platform_connection_id: connection.id }
      end

      def metadata_attrs
        { metadata: connection.metadata.is_a?(Hash) ? connection.metadata : {} }
      end

      def dimension_attrs
        { spend_date: segments[FIELD_DATE], spend_hour: segments[FIELD_HOUR].to_i,
          device: segments[FIELD_DEVICE], network_type: network_type, channel: channel }
      end

      def campaign_attrs
        { platform_campaign_id: campaign[FIELD_ID], campaign_name: campaign[FIELD_NAME],
          campaign_type: campaign_type, currency: currency }
      end

      def metric_attrs
        { spend_micros: metrics[FIELD_COST_MICROS].to_i, impressions: metrics[FIELD_IMPRESSIONS].to_i,
          clicks: metrics[FIELD_CLICKS].to_i, platform_conversions_micros: to_micros(metrics[FIELD_CONVERSIONS]),
          platform_conversion_value_micros: to_micros(metrics[FIELD_CONVERSIONS_VALUE]) }
      end

      def channel
        CampaignChannelMapper.call(
          campaign_type: campaign_type,
          network_type: network_type,
          campaign_id: campaign[FIELD_ID],
          channel_overrides: channel_overrides
        )
      end

      def campaign_type
        @campaign_type ||= campaign[FIELD_ADVERTISING_CHANNEL_TYPE]
      end

      def network_type
        @network_type ||= segments[FIELD_AD_NETWORK_TYPE]
      end

      def to_micros(value)
        (value.to_f * AdSpendRecord::MICRO_UNIT).to_i
      end
    end
  end
end
