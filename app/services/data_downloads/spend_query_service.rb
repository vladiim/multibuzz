# frozen_string_literal: true

module DataDownloads
  class SpendQueryService
    MIN_PER_PAGE = 1
    MAX_PER_PAGE = 1000
    DEFAULT_PER_PAGE = 100
    DEFAULT_DATE_RANGE = "30d"
    MICRO_UNIT = AdSpendRecord::MICRO_UNIT

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
      @data_rows ||= page_records.map { |record| serialize(record) }
    end

    def meta
      {
        total_count: total_count,
        page: page,
        per_page: per_page,
        total_pages: total_pages
      }
    end

    def serialize(record)
      {
        spend_date: record.spend_date.to_s,
        channel: record.channel,
        platform: record.ad_platform_connection.platform,
        campaign_name: record.campaign_name,
        campaign_type: record.campaign_type,
        network_type: record.network_type,
        device: record.device,
        spend_hour: record.spend_hour,
        spend: record.spend.to_f,
        currency: record.currency,
        impressions: record.impressions,
        clicks: record.clicks,
        platform_conversions: major_units(record.platform_conversions_micros),
        platform_conversion_value: major_units(record.platform_conversion_value_micros),
        metadata: record.metadata
      }
    end

    def major_units(micros)
      (micros.to_d / MICRO_UNIT).to_f
    end

    def page_records
      @page_records ||= scoped
        .includes(:ad_platform_connection)
        .order(:spend_date, :spend_hour, :campaign_name)
        .offset((page - 1) * per_page)
        .limit(per_page)
    end

    def scoped
      @scoped ||= SpendIntelligence::Scopes::SpendScope.new(
        account: account,
        date_range: date_range,
        channels: channels,
        test_mode: test_mode
      ).call
    end

    def total_count
      @total_count ||= scoped.count
    end

    def total_pages
      return 0 if total_count.zero?

      (total_count.to_f / per_page).ceil
    end

    def date_range
      @date_range ||= date_range_parser.start_date..date_range_parser.end_date
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
