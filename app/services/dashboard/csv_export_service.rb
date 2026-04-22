# frozen_string_literal: true

module Dashboard
  class CsvExportService
    EXPORT_TYPE = "attribution"

    HEADERS = %w[
      date type name funnel attribution_model algorithm
      channel credit revenue revenue_credit currency
      utm_source utm_medium utm_campaign is_acquisition properties
      journey_position touchpoint_index journey_length days_to_conversion
    ].freeze

    ALGORITHM_LABELS = {
      0 => "first_touch", 1 => "last_touch", 2 => "linear",
      3 => "time_decay", 4 => "u_shaped", 6 => "participation",
      7 => "markov_chain", 8 => "shapley_value"
    }.freeze

    def initialize(account, filter_params)
      @account = account
      @filter_params = filter_params
    end

    def write_to(file_path)
      File.open(file_path, "w") do |file|
        file.write(CSV.generate_line(HEADERS))
        stream_query { |row| file.write(CSV.generate_line(row)) }
      end
      track_export
    end

    private

    def track_export
      Lifecycle::Tracker.track("feature_csv_exported", account, export_type: EXPORT_TYPE)
    end

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
          conversions.converted_at::date AS date,
          'conversion' AS type,
          conversions.conversion_type AS name,
          conversions.funnel,
          attribution_models.name AS attribution_model,
          #{algorithm_case} AS algorithm,
          attribution_credits.channel,
          attribution_credits.credit,
          conversions.revenue,
          attribution_credits.revenue_credit,
          conversions.currency,
          attribution_credits.utm_source,
          attribution_credits.utm_medium,
          attribution_credits.utm_campaign,
          conversions.is_acquisition,
          COALESCE(conversions.properties::text, '{}') AS properties,
          #{journey_position_case} AS journey_position,
          #{touchpoint_index_case} AS touchpoint_index,
          #{journey_length_expr} AS journey_length,
          #{days_to_conversion_expr} AS days_to_conversion
        FROM attribution_credits
        INNER JOIN conversions ON conversions.id = attribution_credits.conversion_id
        INNER JOIN attribution_models ON attribution_models.id = attribution_credits.attribution_model_id
        LEFT JOIN sessions ON sessions.id = attribution_credits.session_id
          AND sessions.account_id = attribution_credits.account_id
        WHERE attribution_credits.account_id = $1
          AND attribution_credits.is_test = $2
          AND conversions.converted_at BETWEEN $3 AND $4
          #{model_filter_clause}
          #{channel_filter_clause}
        ORDER BY conversions.converted_at
      SQL
    end

    def algorithm_case
      branches = ALGORITHM_LABELS.map { |k, v| "WHEN #{k} THEN '#{v}'" }.join(" ")
      "CASE attribution_models.algorithm #{branches} END"
    end

    def journey_position_case
      <<~SQL.squish
        CASE
          WHEN #{no_journey_guard} THEN NULL
          WHEN #{session_not_in_journey} THEN NULL
          WHEN #{journey_index} = 1 THEN 'first_touch'
          WHEN #{journey_index} = #{journey_array_length} THEN 'last_touch'
          ELSE 'assisted'
        END
      SQL
    end

    def touchpoint_index_case
      <<~SQL.squish
        CASE
          WHEN #{no_journey_guard} THEN NULL
          WHEN #{session_not_in_journey} THEN NULL
          ELSE #{journey_index}
        END
      SQL
    end

    def journey_length_expr
      "#{journey_array_length}"
    end

    def days_to_conversion_expr
      <<~SQL.squish
        CASE
          WHEN sessions.started_at IS NULL THEN NULL
          ELSE (conversions.converted_at::date - sessions.started_at::date)
        END
      SQL
    end

    def journey_index
      "array_position(conversions.journey_session_ids, attribution_credits.session_id)"
    end

    def journey_array_length
      "array_length(conversions.journey_session_ids, 1)"
    end

    def no_journey_guard
      "conversions.journey_session_ids IS NULL OR #{journey_array_length} IS NULL"
    end

    def session_not_in_journey
      "#{journey_index} IS NULL"
    end

    def model_filter_clause
      return "" if models.blank?

      ids = models.map(&:id).join(", ")
      "AND attribution_credits.attribution_model_id IN (#{ids})"
    end

    def channel_filter_clause
      return "" if channels == Channels::ALL || channels.blank?

      quoted = channels.map { |c| ActiveRecord::Base.connection.quote(c) }.join(", ")
      "AND attribution_credits.channel IN (#{quoted})"
    end

    def raw_bind_values
      range = date_range.to_range
      [ account.id, test_mode, range.begin.iso8601, range.end.iso8601 ]
    end

    def models
      filter_params[:models]
    end

    def channels
      filter_params[:channels]
    end

    def test_mode
      filter_params[:test_mode] || false
    end

    def date_range
      @date_range ||= DateRangeParser.new(filter_params[:date_range])
    end
  end
end
