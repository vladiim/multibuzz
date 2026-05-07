# frozen_string_literal: true

module ScoreAssessmentHelper
  CTA_BUTTON_LABEL = "Go to mbuzz →"
  CTA_BODY_HAS_ACCOUNT = "Pick up where you left off. Your account is wired and waiting."
  CTA_BODY_NO_ACCOUNT = "Finish setup so the numbers above stop being self-graded by your platforms."

  def current_account_latest_assessment
    @current_account_latest_assessment ||= latest_assessment_for(current_account)
  end

  def account_maturity_level(account)
    latest_assessment_for(account)&.overall_level
  end

  def score_to_app_cta
    if current_account
      { href: dashboard_path, body: CTA_BODY_HAS_ACCOUNT, label: CTA_BUTTON_LABEL }
    else
      { href: signup_path, body: CTA_BODY_NO_ACCOUNT, label: CTA_BUTTON_LABEL }
    end
  end

  private

  def latest_assessment_for(account)
    return nil unless account

    account.score_assessments.order(created_at: :desc).first
  end
end
