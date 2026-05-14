# frozen_string_literal: true

module Dashboard
  class ExportJob < ApplicationJob
    queue_as :default

    def perform(export_id)
      @export = Export.find(export_id)
      return if @export.completed?

      @export.processing!

      generate_and_attach_csv
      complete_export
      broadcast_download_link
    rescue StandardError => e
      @export&.failed! if @export&.persisted?
      raise e
    end

    private

    attr_reader :export

    def generate_and_attach_csv
      Tempfile.create([ export.prefix_id, ".csv" ]) do |tempfile|
        tempfile.close
        export_service.write_to(tempfile.path)
        File.open(tempfile.path, "rb") { |io| attach_csv(io) }
      end
    end

    def attach_csv(io)
      export.csv.attach(io: io, filename: filename, content_type: "text/csv", key: export.blob_key)
    end

    def complete_export
      export.update!(
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
      when DashboardTabs::FUNNEL then FunnelCsvExportService.new(account, service_params)
      when DashboardTabs::SPEND then SpendCsvExportService.new(account, service_params)
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
      "mbuzz-#{export.export_type}-#{Date.current}.csv"
    end
  end
end
