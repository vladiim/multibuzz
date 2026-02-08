# frozen_string_literal: true

module Dashboard
  class ExportsController < BaseController
    def create
      send_data csv_data,
        filename: "multibuzz-export-#{Date.current}.csv",
        type: "text/csv",
        disposition: "attachment"
    end

    private

    def csv_data
      @csv_data ||= CsvExportService.new(current_account, export_params).call
    end

    def export_params
      filter_params.merge(
        models: current_account.attribution_models.active,
        channels: Channels::ALL,
        conversion_filters: []
      )
    end
  end
end
