# frozen_string_literal: true

module Dashboard
  class ExportsController < BaseController
    def create
      send_data csv_data,
        filename: filename,
        type: "text/csv",
        disposition: "attachment"

      broadcast_export_complete
    end

    private

    def csv_data
      @csv_data ||= export_service.call
    end

    def export_service
      case params[:export_type]
      when "funnel" then FunnelCsvExportService.new(current_account, funnel_export_params)
      else CsvExportService.new(current_account, export_params)
      end
    end

    def filename
      type = params[:export_type] == "funnel" ? "funnel" : "conversions"
      "mbuzz-#{type}-#{Date.current}.csv"
    end

    def broadcast_export_complete
      Turbo::StreamsChannel.broadcast_remove_to(
        "account_#{current_account.prefix_id}_exports",
        target: "export-spinner"
      )
    end

    def export_params
      filter_params.merge(
        models: current_account.attribution_models.active,
        channels: Channels::ALL,
        conversion_filters: []
      )
    end

    def funnel_export_params
      filter_params
    end
  end
end
