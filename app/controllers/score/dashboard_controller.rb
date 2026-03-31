# frozen_string_literal: true

module Score
  class DashboardController < ApplicationController
    layout "score"
    before_action :require_login
    before_action :load_assessment

    def show
      return render :no_assessment unless @assessment

      @report = Score::ReportService.new(@assessment).call
    end

    private

    def load_assessment
      @assessment = current_user.score_assessments.order(created_at: :desc).first
    end
  end
end
