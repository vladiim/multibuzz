# frozen_string_literal: true

module DataDownloads
  class ConversionsQueryService
    MIN_PER_PAGE = 1
    MAX_PER_PAGE = 1000
    DEFAULT_PER_PAGE = 100
    DEFAULT_DATE_RANGE = "30d"

    ALGORITHM_LABELS = Dashboard::CsvExportService::ALGORITHM_LABELS
    TYPE = "conversion"

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
      @data_rows ||= page_records.map { |credit| serialize(credit) }
    end

    def meta
      {
        total_count: total_count,
        page: page,
        per_page: per_page,
        total_pages: total_pages
      }
    end

    def serialize(credit) # rubocop:disable Metrics/AbcSize
      conversion = credit.conversion
      session = sessions_by_id[credit.session_id]
      journey_ids = Array(conversion.journey_session_ids)
      journey_index = journey_ids.index(credit.session_id)

      {
        date: conversion.converted_at.to_date.to_s,
        type: TYPE,
        name: conversion.conversion_type,
        funnel: conversion.funnel,
        attribution_model: credit.attribution_model.name,
        algorithm: ALGORITHM_LABELS[credit.attribution_model.algorithm_before_type_cast],
        channel: credit.channel,
        credit: credit.credit.to_f,
        revenue: conversion.revenue&.to_f,
        revenue_credit: credit.revenue_credit&.to_f,
        currency: conversion.currency,
        utm_source: credit.utm_source,
        utm_medium: credit.utm_medium,
        utm_campaign: credit.utm_campaign,
        is_acquisition: conversion.is_acquisition,
        properties: conversion.properties || {},
        journey_position: journey_position(journey_index, journey_ids.length),
        touchpoint_index: journey_index,
        journey_length: journey_ids.length.positive? ? journey_ids.length : nil,
        days_to_conversion: days_to_conversion(session, conversion)
      }
    end

    def journey_position(index, length)
      return nil if index.nil? || length.zero?
      return "first_touch" if index.zero?
      return "last_touch" if index == length - 1

      "assisted"
    end

    def days_to_conversion(session, conversion)
      return nil if session.nil?

      (conversion.converted_at.to_date - session.started_at.to_date).to_i
    end

    def page_records
      @page_records ||= scoped
        .includes(:conversion, :attribution_model)
        .order("conversions.converted_at")
        .offset((page - 1) * per_page)
        .limit(per_page)
    end

    def sessions_by_id
      @sessions_by_id ||= account.sessions
        .where(id: page_records.map(&:session_id).compact.uniq)
        .index_by(&:id)
    end

    def scoped
      @scoped ||= Dashboard::Scopes::FilteredCreditsScope.new(
        account: account,
        models: attribution_models,
        date_range: date_range_parser,
        channels: channels,
        test_mode: test_mode
      ).call
    end

    def attribution_models
      @attribution_models ||= account.attribution_models.active
    end

    def total_count
      @total_count ||= scoped.count
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
