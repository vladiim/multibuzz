# frozen_string_literal: true

module Dashboard
  class CsvExportService
    HEADERS = %w[
      date type name funnel attribution_model algorithm
      channel credit revenue revenue_credit currency
      utm_source utm_medium utm_campaign is_acquisition properties
      journey_position touchpoint_index journey_length days_to_conversion
    ].freeze

    def initialize(account, filter_params)
      @account = account
      @filter_params = filter_params
    end

    def write_to(file_path)
      File.open(file_path, "w") do |file|
        file.write(CSV.generate_line(HEADERS))

        credits_scope.find_in_batches(batch_size: 500) do |batch|
          preload_journey_sessions(batch)
          batch.each { |credit| file.write(CSV.generate_line(row_for(credit))) }
        end
      end
    end

    private

    attr_reader :account, :filter_params

    def row_for(credit)
      conversion = credit.conversion
      journey = journey_data(credit, conversion)

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
        (conversion.properties || {}).to_json,
        journey[:position],
        journey[:index]&.to_s,
        journey[:length]&.to_s,
        journey[:days]&.to_s
      ]
    end

    def journey_data(credit, conversion)
      journey_ids = conversion.journey_session_ids
      return {} if journey_ids.blank?

      index = journey_ids.index(credit.session_id)
      return {} if index.nil?

      length = journey_ids.length
      session = @sessions_by_id[credit.session_id]

      {
        position: journey_position_for(index, length),
        index: index + 1,
        length: length,
        days: session ? (conversion.converted_at.to_date - session.started_at.to_date).to_i : nil
      }
    end

    def journey_position_for(index, length)
      return AttributionAlgorithms::FIRST_TOUCH if index.zero?
      return AttributionAlgorithms::LAST_TOUCH if index == length - 1

      AttributionAlgorithms::ASSISTED
    end

    def preload_journey_sessions(credits)
      session_ids = credits.flat_map { |c| c.conversion.journey_session_ids || [] }.uniq
      @sessions_by_id = session_ids.any? ? account.sessions.where(id: session_ids).index_by(&:id) : {}
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
