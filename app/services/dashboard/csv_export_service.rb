# frozen_string_literal: true

module Dashboard
  class CsvExportService
    HEADERS = %w[
      date type name funnel attribution_model algorithm
      channel credit revenue revenue_credit currency
      utm_source utm_medium utm_campaign is_acquisition properties
    ].freeze

    def initialize(account, filter_params)
      @account = account
      @filter_params = filter_params
    end

    def call
      CSV.generate do |csv|
        csv << HEADERS
        credits_scope.find_each { |credit| csv << row_for(credit) }
      end
    end

    private

    attr_reader :account, :filter_params

    def row_for(credit)
      conversion = credit.conversion

      [
        conversion.converted_at.to_date.to_s,
        FunnelStages::CONVERSION,
        conversion.conversion_type,
        conversion.funnel,
        credit.attribution_model.name,
        credit.attribution_model.algorithm,
        credit.channel,
        credit.credit.to_s,
        conversion.revenue&.to_s,
        credit.revenue_credit&.to_s,
        conversion.currency,
        credit.utm_source,
        credit.utm_medium,
        credit.utm_campaign,
        conversion.is_acquisition.to_s,
        (conversion.properties || {}).to_json
      ]
    end

    def credits_scope
      @credits_scope ||= Scopes::FilteredCreditsScope.new(
        account: account,
        models: filter_params[:models],
        date_range: date_range,
        channels: filter_params[:channels],
        conversion_filters: filter_params[:conversion_filters] || [],
        test_mode: filter_params[:test_mode] || false
      ).call.includes(:conversion, :attribution_model)
    end

    def date_range
      @date_range ||= DateRangeParser.new(filter_params[:date_range])
    end
  end
end
