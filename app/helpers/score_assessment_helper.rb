# frozen_string_literal: true

module ScoreAssessmentHelper
  def current_account_latest_assessment
    @current_account_latest_assessment ||= latest_assessment_for(current_account)
  end

  def account_maturity_level(account)
    latest_assessment_for(account)&.overall_level
  end

  private

  def latest_assessment_for(account)
    return nil unless account

    account.score_assessments.order(created_at: :desc).first
  end
end
