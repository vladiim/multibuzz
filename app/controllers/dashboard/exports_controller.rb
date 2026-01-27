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
      @csv_data ||= CsvExportService.new(current_account, filter_params).call
    end
  end
end
