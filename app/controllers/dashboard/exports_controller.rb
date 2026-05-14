# frozen_string_literal: true

module Dashboard
  class ExportsController < BaseController
    skip_marketing_analytics

    def create
      export = current_account.exports.create!(
        export_type: export_type,
        filter_params: serialized_filter_params
      )

      ExportJob.perform_later(export.id)

      redirect_to dashboard_export_status_path(id: export.prefix_id)
    end

    def show
      @export = current_account.exports.find_by_prefix_id!(params[:id])
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    def download
      export = current_account.exports.find_by_prefix_id!(params[:id])

      return redirect_to dashboard_export_status_path(id: export.prefix_id) unless export.completed?
      return head :gone if export.expired?
      return head :gone unless export.csv.attached?

      redirect_to export.download_url, allow_other_host: true
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    private

    def export_type
      params[:export_type].presence_in(Export::EXPORT_TYPES) || DashboardTabs::CONVERSIONS
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
