# frozen_string_literal: true

module AdPlatforms
  module Meta
    # Pure parser. Takes a single Meta /insights row + the connection it came
    # from, returns a hash of AdSpendRecord attributes ready for upsert. No HTTP,
    # no IO, no DB.
    class RowParser
      def self.call(row, connection:, channel_overrides: nil)
        new(row, connection: connection, channel_overrides: channel_overrides).call
      end

      def initialize(row, connection:, channel_overrides: nil)
        @row = row
        @connection = connection
        @channel_overrides = channel_overrides
      end

      def call
        connection_attrs.merge(dimension_attrs).merge(campaign_attrs).merge(metric_attrs).merge(metadata_attrs)
      end

      private

      attr_reader :row, :connection, :channel_overrides

      def connection_attrs
        { account_id: connection.account_id, ad_platform_connection_id: connection.id }
      end

      def metadata_attrs
        { metadata: connection.metadata.is_a?(Hash) ? connection.metadata : {} }
      end

      def dimension_attrs
        {
          spend_date: row["date_start"],
          spend_hour: spend_hour,
          device: row.fetch("device_platform", "ALL"),
          network_type: nil,
          channel: channel
        }
      end

      def campaign_attrs
        {
          platform_campaign_id: row["campaign_id"],
          campaign_name: row["campaign_name"],
          campaign_type: row["objective"],
          currency: connection.currency
        }
      end

      def metric_attrs
        {
          spend_micros: to_micros(row["spend"]),
          impressions: row["impressions"].to_i,
          clicks: row["clicks"].to_i,
          platform_conversions_micros: sum_action_micros(row["actions"]),
          platform_conversion_value_micros: sum_action_micros(row["action_values"])
        }
      end

      def channel
        CampaignChannelMapper.call(campaign_id: row["campaign_id"], channel_overrides: channel_overrides)
      end

      def spend_hour
        row.fetch("hourly_stats_aggregated_by_advertiser_time_zone", "0").to_s.split(":").first.to_i
      end

      def sum_action_micros(actions)
        Array(actions)
          .select { |action| PURCHASE_ACTION_TYPES.include?(action["action_type"]) }
          .sum { |action| to_micros(action["value"]) }
      end

      def to_micros(value)
        (value.to_f * AdSpendRecord::MICRO_UNIT).to_i
      end
    end
  end
end
