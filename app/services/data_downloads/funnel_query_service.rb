# frozen_string_literal: true

module DataDownloads
  class FunnelQueryService
    MIN_PER_PAGE = 1
    MAX_PER_PAGE = 1000
    DEFAULT_PER_PAGE = 100
    DEFAULT_DATE_RANGE = "30d"

    def initialize(account, params)
      @account = account
      @params = params
    end

    def call
      { data: data_rows, meta: meta }
    end

    private

    attr_reader :account, :params

    def data_rows
      @data_rows ||= sorted_rows.slice((page - 1) * per_page, per_page) || []
    end

    def meta
      {
        total_count: total_count,
        page: page,
        per_page: per_page,
        total_pages: total_pages
      }
    end

    def sorted_rows
      @sorted_rows ||= (visit_rows + event_rows + conversion_rows).sort_by { |row| row[:_sort_key] }
                                                                  .map { |row| row.except(:_sort_key) }
    end

    def visit_rows
      return [] if funnel.present?

      sessions_scope.call.map do |session|
        {
          _sort_key: session.started_at,
          date: session.started_at.to_date.to_s,
          type: FunnelStages::VISIT,
          name: nil,
          funnel: nil,
          channel: session.channel,
          utm_source: session.initial_utm&.dig("utm_source"),
          utm_medium: session.initial_utm&.dig("utm_medium"),
          utm_campaign: session.initial_utm&.dig("utm_campaign"),
          revenue: nil,
          currency: nil,
          is_acquisition: nil,
          properties: nil,
          session_id: session.id
        }
      end
    end

    def event_rows # rubocop:disable Metrics/AbcSize
      events_scope.call.includes(:session).map do |event|
        session = event.session
        {
          _sort_key: event.occurred_at,
          date: event.occurred_at.to_date.to_s,
          type: FunnelStages::EVENT,
          name: event.event_type,
          funnel: event.funnel,
          channel: session&.channel,
          utm_source: session&.initial_utm&.dig("utm_source"),
          utm_medium: session&.initial_utm&.dig("utm_medium"),
          utm_campaign: session&.initial_utm&.dig("utm_campaign"),
          revenue: nil,
          currency: nil,
          is_acquisition: nil,
          properties: event.properties || {},
          session_id: session&.id
        }
      end
    end

    def conversion_rows # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
      conversions = conversions_scope.call.to_a
      session_lookup = account.sessions.where(id: conversions.map(&:session_id).compact.uniq).index_by(&:id)

      conversions.map do |conversion|
        session = session_lookup[conversion.session_id]
        {
          _sort_key: conversion.converted_at,
          date: conversion.converted_at.to_date.to_s,
          type: FunnelStages::CONVERSION,
          name: conversion.conversion_type,
          funnel: conversion.funnel,
          channel: session&.channel,
          utm_source: session&.initial_utm&.dig("utm_source"),
          utm_medium: session&.initial_utm&.dig("utm_medium"),
          utm_campaign: session&.initial_utm&.dig("utm_campaign"),
          revenue: conversion.revenue&.to_f,
          currency: conversion.currency,
          is_acquisition: conversion.is_acquisition,
          properties: conversion.properties || {},
          session_id: conversion.session_id
        }
      end
    end

    def sessions_scope
      @sessions_scope ||= Dashboard::Scopes::SessionsScope.new(
        account: account,
        date_range: date_range_parser,
        channels: channels,
        test_mode: test_mode
      )
    end

    def events_scope
      @events_scope ||= Dashboard::Scopes::EventsScope.new(
        account: account,
        date_range: date_range_parser,
        channels: channels,
        test_mode: test_mode,
        funnel: funnel
      )
    end

    def conversions_scope
      @conversions_scope ||= Dashboard::Scopes::ConversionsScope.new(
        account: account,
        date_range: date_range_parser,
        channels: channels,
        test_mode: test_mode,
        funnel: funnel
      )
    end

    def total_count
      @total_count ||= visit_count + events_scope.call.count + conversions_scope.call.count
    end

    def visit_count
      funnel.present? ? 0 : sessions_scope.call.count
    end

    def total_pages
      return 0 if total_count.zero?

      (total_count.to_f / per_page).ceil
    end

    def date_range_parser
      @date_range_parser ||= Dashboard::DateRangeParser.new(params[:date_range].presence || DEFAULT_DATE_RANGE)
    end

    def channels
      @channels ||= params[:channels].presence || Channels::ALL
    end

    def funnel
      params[:funnel].presence
    end

    def test_mode
      ActiveModel::Type::Boolean.new.cast(params[:test_mode]) || false
    end

    def page
      @page ||= [ params[:page].to_i, 1 ].max
    end

    def per_page
      @per_page ||= raw_per_page.clamp(MIN_PER_PAGE, MAX_PER_PAGE)
    end

    def raw_per_page
      params[:per_page].present? ? params[:per_page].to_i : DEFAULT_PER_PAGE
    end
  end
end
