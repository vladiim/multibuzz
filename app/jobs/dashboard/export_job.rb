# frozen_string_literal: true

module Dashboard
  class ExportJob < ApplicationJob
    queue_as :default

    def perform(export_id)
      @export = Export.find(export_id)
      @export.processing!

      generate_csv
      complete_export
      broadcast_download_link
    rescue StandardError => e
      @export&.failed! if @export&.persisted?
      raise e
    end

    private

    attr_reader :export

    def generate_csv
      FileUtils.mkdir_p(export_dir)
      export_service.write_to(file_path)
    end

    def complete_export
      export.update!(
        file_path: file_path.to_s,
        filename: filename,
        status: :completed,
        completed_at: Time.current,
        expires_at: Export::EXPIRY_DURATION.from_now
      )
    end

    def broadcast_download_link
      Turbo::StreamsChannel.broadcast_replace_to(
        "export_#{export.prefix_id}",
        target: "export-status",
        partial: "dashboard/exports/download_ready",
        locals: { export: export }
      )
    end

    def export_service
      case export.export_type
      when "funnel" then FunnelCsvExportService.new(account, service_params)
      else CsvExportService.new(account, export_params)
      end
    end

    def service_params
      filter_params.merge(
        channels: filter_params[:channels] || Channels::ALL,
        test_mode: filter_params[:test_mode] || false
      )
    end

    def export_params
      service_params.merge(
        models: account.attribution_models.active,
        channels: Channels::ALL,
        conversion_filters: []
      )
    end

    def filter_params
      @filter_params ||= export.filter_params.deep_symbolize_keys
    end

    def account
      @account ||= export.account
    end

    def filename
      type = export.export_type == "funnel" ? "funnel" : "conversions"
      "mbuzz-#{type}-#{Date.current}.csv"
    end

    def file_path
      @file_path ||= export_dir.join("#{export.prefix_id}.csv")
    end

    def export_dir
      Rails.root.join("tmp/exports")
    end
  end
end
