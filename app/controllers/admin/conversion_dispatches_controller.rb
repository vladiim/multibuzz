# frozen_string_literal: true

# Operator view of outbound conversion-feedback dispatches (Meta CAPI,
# later Google EC). Cross-account; filtering lives in
# ConversionDispatches::AdminFilterQuery. Inherits
# skip_marketing_analytics + require_admin from Admin::BaseController.
#
# Sensitive: dispatch rows include hashed user identifiers in `payload`
# and platform trace IDs in `response`. Admin-only is the gate.
module Admin
  class ConversionDispatchesController < BaseController
    include Pagination

    per_page 50

    def index
      @dispatches = paginate(filtered_dispatches)
      @filter_params = filter_params
    end

    def show
      @dispatch = ConversionDispatch.find_by_prefix_id!(params[:id])
    end

    # Operator-initiated retry. Bypasses Conversions::DispatchService
    # (which would re-check the feature flag and event_type_mapping)
    # because an operator clicking "retry" knows what they're doing
    # and shouldn't be silently swallowed. The dispatcher's
    # existing_delivered_dispatch guard still no-ops for already-
    # delivered rows.
    def retry
      dispatch = ConversionDispatch.find_by_prefix_id!(params[:id])
      OutboundConversionJob.perform_later(dispatch.conversion_id, dispatch.conversion_destination_id)
      redirect_to admin_conversion_dispatch_path(dispatch.prefix_id), notice: "Retry enqueued."
    end

    private

    def filtered_dispatches
      ConversionDispatches::AdminFilterQuery.new(filter_params).call
    end

    def filter_params
      @filter_params ||= params.permit(:status, :account_id, :conversion_destination_id, :from, :to)
    end
  end
end
