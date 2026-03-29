# frozen_string_literal: true

module Score
  class DashboardController < ApplicationController
    layout "score"
    before_action :require_login

    def show
      @assessment = current_user.score_assessments.order(created_at: :desc).first
    end
  end
end
