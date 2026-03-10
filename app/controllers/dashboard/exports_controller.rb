# frozen_string_literal: true

module Dashboard
  class ExportsController < BaseController
    def create
      export = current_account.exports.create!(
        export_type: export_type,
        filter_params: serialized_filter_params
      )

      ExportJob.perform_later(export.id)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "export-spinner",
            partial: "dashboard/exports/processing"
          )
        end
        format.html { redirect_to dashboard_path, notice: "Export started" }
      end
    end

    def show
      export = current_account.exports.completed.find_by_prefix_id!(params[:id])

      if export.expired?
        head :gone
      else
        send_file export.file_path,
          filename: export.filename,
          type: "text/csv",
          disposition: "attachment"
      end
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    private

    def export_type
      params[:export_type].presence_in(Export::EXPORT_TYPES) || "conversions"
    end

    def serialized_filter_params
      {
        date_range: date_range_param,
        channels: channels_param,
        journey_position: journey_position_param,
        metric: metric_param,
        funnel: funnel_param,
        test_mode: test_mode?
      }
    end

    def test_mode?
      params[:view_mode] == "test"
    end
  end
end
