# frozen_string_literal: true

module Dashboard
  class FunnelCsvExportService
    HEADERS = %w[
      date type name funnel channel
      utm_source utm_medium utm_campaign
      revenue currency is_acquisition properties
    ].freeze

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
        (#{visits_sql})
        UNION ALL
        (#{events_sql})
        UNION ALL
        (#{conversions_sql})
        ORDER BY 1
      SQL
    end

    def visits_sql
      <<~SQL
        SELECT
          sessions.started_at::date AS date,
          'visit' AS type,
          NULL AS name,
          NULL AS funnel,
          sessions.channel,
          sessions.initial_utm ->> 'utm_source' AS utm_source,
          sessions.initial_utm ->> 'utm_medium' AS utm_medium,
          sessions.initial_utm ->> 'utm_campaign' AS utm_campaign,
          NULL::numeric AS revenue,
          NULL AS currency,
          NULL::boolean AS is_acquisition,
          NULL AS properties
        FROM sessions
        WHERE sessions.account_id = $1
          AND sessions.is_test = $2
          AND sessions.suspect = false
          AND sessions.started_at BETWEEN $3 AND $4
          #{channel_filter("sessions")}
      SQL
    end

    def events_sql
      <<~SQL
        SELECT
          events.occurred_at::date AS date,
          'event' AS type,
          events.event_type AS name,
          events.funnel,
          s.channel,
          s.initial_utm ->> 'utm_source' AS utm_source,
          s.initial_utm ->> 'utm_medium' AS utm_medium,
          s.initial_utm ->> 'utm_campaign' AS utm_campaign,
          NULL::numeric AS revenue,
          NULL AS currency,
          NULL::boolean AS is_acquisition,
          COALESCE(events.properties::text, '{}') AS properties
        FROM events
        INNER JOIN sessions s ON s.id = events.session_id AND s.account_id = events.account_id
        WHERE events.account_id = $1
          AND events.is_test = $2
          AND events.occurred_at BETWEEN $3 AND $4
          #{channel_filter("s")}
          #{funnel_filter}
      SQL
    end

    def conversions_sql
      <<~SQL
        SELECT
          conversions.converted_at::date AS date,
          'conversion' AS type,
          conversions.conversion_type AS name,
          conversions.funnel,
          s.channel,
          s.initial_utm ->> 'utm_source' AS utm_source,
          s.initial_utm ->> 'utm_medium' AS utm_medium,
          s.initial_utm ->> 'utm_campaign' AS utm_campaign,
          conversions.revenue,
          conversions.currency,
          conversions.is_acquisition,
          COALESCE(conversions.properties::text, '{}') AS properties
        FROM conversions
        LEFT JOIN sessions s ON s.id = conversions.session_id AND s.account_id = conversions.account_id
        WHERE conversions.account_id = $1
          AND conversions.is_test = $2
          AND conversions.converted_at BETWEEN $3 AND $4
          #{channel_filter("s")}
      SQL
    end

    def channel_filter(table_alias)
      return "" if channels == Channels::ALL || channels.blank?

      quoted = channels.map { |c| ActiveRecord::Base.connection.quote(c) }.join(", ")
      "AND #{table_alias}.channel IN (#{quoted})"
    end

    def funnel_filter
      return "" if funnel_param.blank? || funnel_param == "all"

      "AND events.funnel = #{ActiveRecord::Base.connection.quote(funnel_param)}"
    end

    def raw_bind_values
      range = date_range.to_range
      [ account.id, test_mode, range.begin.iso8601, range.end.iso8601 ]
    end

    def channels
      filter_params[:channels] || Channels::ALL
    end

    def funnel_param
      filter_params[:funnel]
    end

    def test_mode
      filter_params[:test_mode] || false
    end

    def date_range
      @date_range ||= DateRangeParser.new(filter_params[:date_range])
    end
  end
end
