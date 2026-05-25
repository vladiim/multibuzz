# frozen_string_literal: true

require "test_helper"

class Score::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "redirects to login when not authenticated" do
    get score_dashboard_path

    assert_redirected_to login_path
  end

  test "shows no-assessment state when current account has none" do
    sign_in_as(users(:three))
    get score_dashboard_path

    assert_response :success
    assert_select "a[href='#{score_path}']"
  end

  test "shows report for current account with an assessment" do
    create_assessment(account: accounts(:one), level: 2)
    sign_in_as(users(:one))
    get score_dashboard_path

    assert_response :success
    assert_select ".report-level-badge", text: /Level 2/
    assert_select ".report-tab", minimum: 4
  end

  test "uses most recent assessment for the current account" do
    create_assessment(account: accounts(:one), level: 1)
    create_assessment(account: accounts(:one), level: 3)
    sign_in_as(users(:one))
    get score_dashboard_path

    assert_response :success
    assert_select ".report-level-badge", text: /Level 3/
  end

  test "isolates assessments by account" do
    create_assessment(account: accounts(:two), level: 4)
    sign_in_as(users(:one))
    get score_dashboard_path

    assert_response :success
    assert_select ".report-level-badge", false, "must not show another account's score"
    assert_select "a[href='#{score_path}']"
  end

  test "renders the to-app CTA above the tabs when an assessment is present" do
    create_assessment(account: accounts(:one), level: 2)
    sign_in_as(users(:one))
    get score_dashboard_path

    assert_response :success
    assert_select ".report-to-app-cta"
    assert_select ".report-to-app-cta-btn[href='#{dashboard_path}']", text: /Go to mbuzz/
  end

  private

  def create_assessment(account:, level:)
    ScoreAssessment.create!(
      account: account,
      overall_score: level.to_f,
      overall_level: level,
      dimension_scores: {
        "reporting" => 2.0, "attribution" => 2.0, "experimentation" => 2.0,
        "forecasting" => 2.0, "channels" => 2.0, "infrastructure" => 2.0
      },
      answers: [],
      context: {}
    )
  end
end
