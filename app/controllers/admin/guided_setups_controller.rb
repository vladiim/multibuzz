# frozen_string_literal: true

# Operator view of Guided Setup concierge engagements. Cross-account;
# inherits skip_marketing_analytics + require_admin from Admin::BaseController.
module Admin
  class GuidedSetupsController < BaseController
    before_action :set_guided_setup, only: %i[show update record_milestone]

    def index
      @guided_setups = GuidedSetup.includes(:account).order(created_at: :desc)
    end

    def show; end

    def update
      @guided_setup.update!(guided_setup_params)
      redirect_to admin_guided_setup_path(@guided_setup), notice: "Engagement updated."
    end

    def record_milestone
      @guided_setup.record_milestone!(params[:milestone])
      redirect_to admin_guided_setup_path(@guided_setup), notice: "Milestone recorded."
    rescue ArgumentError
      redirect_to admin_guided_setup_path(@guided_setup), alert: "Unknown milestone."
    end

    private

    def set_guided_setup
      @guided_setup = GuidedSetup.find(params[:id])
    end

    def guided_setup_params
      params.require(:guided_setup).permit(:specialist_name, :notes)
    end
  end
end
