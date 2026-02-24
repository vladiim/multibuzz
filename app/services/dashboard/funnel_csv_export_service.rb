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

    def call
      CSV.generate do |csv|
        csv << HEADERS
        sorted_rows.each { |row| csv << row }
      end
    end

    private

    attr_reader :account, :filter_params

    def sorted_rows
      (visit_rows + event_rows + conversion_rows).sort_by { |row| row[0] }
    end

    # --- Visits ---

    def visit_rows
      sessions_scope.find_each.map { |session| visit_row(session) }
    end

    def visit_row(session)
      [
        session.started_at.to_date.to_s,
        FunnelStages::VISIT,
        nil,
        nil,
        session.channel,
        utm_value(session, UtmKeys::SOURCE),
        utm_value(session, UtmKeys::MEDIUM),
        utm_value(session, UtmKeys::CAMPAIGN),
        nil,
        nil,
        nil,
        nil
      ]
    end

    # --- Events ---

    def event_rows
      events_scope.includes(:session).find_each.map { |event| event_row(event) }
    end

    def event_row(event)
      session = event.session

      [
        event.occurred_at.to_date.to_s,
        FunnelStages::EVENT,
        event.event_type,
        event.funnel,
        session&.channel,
        utm_value(session, UtmKeys::SOURCE),
        utm_value(session, UtmKeys::MEDIUM),
        utm_value(session, UtmKeys::CAMPAIGN),
        nil,
        nil,
        nil,
        (event.properties || {}).to_json
      ]
    end

    # --- Conversions ---

    def conversion_rows
      conversions_with_sessions.map { |conversion, session| conversion_row(conversion, session) }
    end

    def conversions_with_sessions
      conversions_scope.find_each.map do |conversion|
        session = sessions_by_id[conversion.session_id]
        [ conversion, session ]
      end
    end

    def sessions_by_id
      @sessions_by_id ||= begin
        ids = conversions_scope.pluck(:session_id).compact
        account.sessions.where(id: ids).index_by(&:id)
      end
    end

    def conversion_row(conversion, session)
      [
        conversion.converted_at.to_date.to_s,
        FunnelStages::CONVERSION,
        conversion.conversion_type,
        conversion.funnel,
        session&.channel,
        utm_value(session, UtmKeys::SOURCE),
        utm_value(session, UtmKeys::MEDIUM),
        utm_value(session, UtmKeys::CAMPAIGN),
        conversion.revenue&.to_s,
        conversion.currency,
        conversion.is_acquisition.to_s,
        (conversion.properties || {}).to_json
      ]
    end

    # --- Shared ---

    def utm_value(session, key)
      return nil unless session

      session.initial_utm&.dig(key) || session.initial_utm&.dig(key.to_sym)
    end

    # --- Scopes ---

    def sessions_scope
      Scopes::SessionsScope.new(
        account: account,
        date_range: date_range,
        channels: filter_params[:channels] || Channels::ALL,
        test_mode: filter_params[:test_mode] || false
      ).call
    end

    def events_scope
      Scopes::EventsScope.new(
        account: account,
        date_range: date_range,
        channels: filter_params[:channels] || Channels::ALL,
        funnel: filter_params[:funnel],
        test_mode: filter_params[:test_mode] || false
      ).call
    end

    def conversions_scope
      @conversions_scope ||= Scopes::ConversionsScope.new(
        account: account,
        date_range: date_range,
        channels: filter_params[:channels] || Channels::ALL,
        test_mode: filter_params[:test_mode] || false
      ).call
    end

    def date_range
      @date_range ||= DateRangeParser.new(filter_params[:date_range])
    end
  end
end
