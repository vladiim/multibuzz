# frozen_string_literal: true

require "test_helper"

class ScoreAssessmentHelperTest < ActionView::TestCase
  include ScoreAssessmentHelper

  # --- current_account_latest_assessment ---

  test "returns nil when there is no current account" do
    stub_current_account(nil)

    assert_nil current_account_latest_assessment
  end

  test "returns nil when current account has no assessments" do
    stub_current_account(account_one)

    assert_nil current_account_latest_assessment
  end

  test "returns most recent assessment for current account" do
    create_assessment(account: account_one, level: 1, created_at: 2.days.ago)
    latest = create_assessment(account: account_one, level: 3, created_at: 1.hour.ago)
    stub_current_account(account_one)

    assert_equal latest, current_account_latest_assessment
  end

  test "ignores assessments from other accounts" do
    create_assessment(account: account_two, level: 4)
    stub_current_account(account_one)

    assert_nil current_account_latest_assessment
  end

  # --- account_maturity_level ---

  test "account_maturity_level returns the level for an assessed account" do
    create_assessment(account: account_one, level: 2)

    assert_equal 2, account_maturity_level(account_one)
  end

  test "account_maturity_level returns nil for an unassessed account" do
    assert_nil account_maturity_level(account_one)
  end

  test "account_maturity_level returns nil for a nil account" do
    assert_nil account_maturity_level(nil)
  end

  # --- score_to_app_cta ---

  test "score_to_app_cta points to dashboard when an account is current" do
    stub_current_account(account_one)

    cta = score_to_app_cta

    assert_equal dashboard_path, cta[:href]
    assert_equal ScoreAssessmentHelper::CTA_BUTTON_LABEL, cta[:label]
    assert_equal ScoreAssessmentHelper::CTA_BODY_HAS_ACCOUNT, cta[:body]
  end

  test "score_to_app_cta points to signup when no account is current" do
    stub_current_account(nil)

    cta = score_to_app_cta

    assert_equal signup_path, cta[:href]
    assert_equal ScoreAssessmentHelper::CTA_BUTTON_LABEL, cta[:label]
    assert_equal ScoreAssessmentHelper::CTA_BODY_NO_ACCOUNT, cta[:body]
  end

  private

  def account_one = @account_one ||= accounts(:one)
  def account_two = @account_two ||= accounts(:two)

  def stub_current_account(account)
    define_singleton_method(:current_account) { account }
  end

  def create_assessment(account:, level:, created_at: Time.current)
    ScoreAssessment.create!(
      account: account,
      overall_score: level.to_f,
      overall_level: level,
      created_at: created_at,
      dimension_scores: {},
      answers: []
    )
  end
end
