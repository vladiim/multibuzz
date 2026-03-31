# frozen_string_literal: true

require "test_helper"

class Score::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "redirects to login when not authenticated" do
    get score_dashboard_path

    assert_redirected_to login_path
  end

  test "shows no-assessment state for user without assessment" do
    sign_in_as(users(:three))
    get score_dashboard_path

    assert_response :success
    assert_select "a[href='#{score_path}']"
  end

  test "shows report for user with assessment" do
    user = users(:one)
    ScoreAssessment.create!(
      user: user,
      overall_score: 2.3,
      overall_level: 2,
      dimension_scores: {
        "reporting" => 2.5, "attribution" => 1.5, "experimentation" => 1.0,
        "forecasting" => 2.5, "channels" => 3.0, "infrastructure" => 2.0
      },
      answers: [],
      context: { "ad_spend" => "100k-500k", "company_size" => "51-200", "role" => "marketing" }
    )

    sign_in_as(user)
    get score_dashboard_path

    assert_response :success
    assert_select ".report-level-badge"
    assert_select ".report-tab", minimum: 4
  end

  test "uses most recent assessment when user has multiple" do
    user = users(:one)
    ScoreAssessment.create!(user: user, overall_score: 1.5, overall_level: 1, dimension_scores: {}, answers: [])
    latest = ScoreAssessment.create!(user: user, overall_score: 3.0, overall_level: 3, dimension_scores: {}, answers: [])

    sign_in_as(user)
    get score_dashboard_path

    assert_response :success
    assert_select ".report-level-badge", text: /Level 3/
  end
end
