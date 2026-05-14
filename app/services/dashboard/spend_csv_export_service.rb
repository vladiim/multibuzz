# frozen_string_literal: true

module Dashboard
  class SpendCsvExportService
    HEADERS = %w[
      spend_date channel platform campaign_name campaign_type network_type
      device spend_hour spend currency impressions clicks
      platform_conversions platform_conversion_value metadata
    ].freeze

    MICRO_UNIT = AdSpendRecord::MICRO_UNIT

    def initialize(account, filter_params)
      @account = account
      @filter_params = filter_params
    end

    def write_to(file_path)
      File.open(file_path, "w") do |file|
        file.write(CSV.generate_line(HEADERS))
        stream_query { |row| file.write(CSV.generate_line(row)) }
      end
    end

    private

    attr_reader :account, :filter_params

    def stream_query(&block)
      conn = ActiveRecord::Base.connection.raw_connection
      conn.send_query_params(export_sql, raw_bind_values)
      conn.set_single_row_mode

      while result = conn.get_result
        result.each_row(&block)
        result.clear
      end
    end

    def export_sql
      <<~SQL
        SELECT
          ad_spend_records.spend_date::text AS spend_date,
          ad_spend_records.channel,
          #{platform_case_sql} AS platform,
          ad_spend_records.campaign_name,
          ad_spend_records.campaign_type,
          ad_spend_records.network_type,
          ad_spend_records.device,
          ad_spend_records.spend_hour,
          (ad_spend_records.spend_micros::numeric / #{MICRO_UNIT}) AS spend,
          ad_spend_records.currency,
          ad_spend_records.impressions,
          ad_spend_records.clicks,
          (ad_spend_records.platform_conversions_micros::numeric / #{MICRO_UNIT}) AS platform_conversions,
          (ad_spend_records.platform_conversion_value_micros::numeric / #{MICRO_UNIT}) AS platform_conversion_value,
          ad_spend_records.metadata::text AS metadata
        FROM ad_spend_records
        INNER JOIN ad_platform_connections
          ON ad_platform_connections.id = ad_spend_records.ad_platform_connection_id
          AND ad_platform_connections.account_id = ad_spend_records.account_id
        WHERE ad_spend_records.account_id = $1
          AND ad_spend_records.is_test = $2
          AND ad_spend_records.spend_date BETWEEN $3 AND $4
          #{channel_filter}
        ORDER BY ad_spend_records.spend_date, ad_spend_records.spend_hour, ad_spend_records.campaign_name
      SQL
    end

    def platform_case_sql
      cases = AdPlatformConnection.platforms.map do |name, value|
        "WHEN #{value.to_i} THEN #{ActiveRecord::Base.connection.quote(name)}"
      end.join(" ")
      "CASE ad_platform_connections.platform #{cases} ELSE NULL END"
    end

    def channel_filter
      return "" if channels == Channels::ALL || channels.blank?

      quoted = channels.map { |c| ActiveRecord::Base.connection.quote(c) }.join(", ")
      "AND ad_spend_records.channel IN (#{quoted})"
    end

    def raw_bind_values
      range = date_range.to_range
      [ account.id, test_mode, range.begin.to_date.iso8601, range.end.to_date.iso8601 ]
    end

    def channels
      filter_params[:channels] || Channels::ALL
    end

    def test_mode
      filter_params[:test_mode] || false
    end

    def date_range
      @date_range ||= DateRangeParser.new(filter_params[:date_range])
    end
  end
end
