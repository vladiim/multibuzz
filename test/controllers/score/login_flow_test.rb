# frozen_string_literal: true

require "test_helper"

class Score::LoginFlowTest < ActionDispatch::IntegrationTest
  test "login with return_to redirects to score dashboard instead of main dashboard" do
    get login_path(return_to: score_dashboard_path)

    post login_path, params: { email: users(:one).email, password: "password123" }

    assert_redirected_to score_dashboard_path
  end

  test "login with claim_token claims the unclaimed assessment" do
    assessment = ScoreAssessment.create!(
      overall_score: 2.0,
      overall_level: 2,
      dimension_scores: {},
      answers: []
    )
    token = assessment.claim_token

    get login_path(return_to: score_dashboard_path, claim_token: token)

    post login_path, params: { email: users(:one).email, password: "password123" }

    assessment.reload

    assert_equal users(:one).id, assessment.user_id
    assert_nil assessment.claim_token
  end

  test "login without return_to still goes to main dashboard" do
    post login_path, params: { email: users(:one).email, password: "password123" }

    assert_redirected_to dashboard_path
  end

  test "score signup page login link includes return_to and claim_token" do
    get score_signup_path(claim_token: "test_token_123")

    assert_response :success
    assert_select "a[href*='return_to']"
    assert_select "a[href*='claim_token']"
  end

  test "return_to only accepts relative paths" do
    get login_path(return_to: "https://evil.com/steal")

    post login_path, params: { email: users(:one).email, password: "password123" }

    assert_redirected_to dashboard_path
  end

  test "require_login preserves return_to for score dashboard" do
    get score_dashboard_path

    assert_redirected_to login_path
    follow_redirect!

    post login_path, params: { email: users(:one).email, password: "password123" }

    assert_redirected_to score_dashboard_path
  end

  test "logged-in user visiting login page is redirected to dashboard" do
    sign_in_as(users(:one))

    get login_path

    assert_redirected_to dashboard_path
  end

  test "logged-in user visiting login with return_to is redirected there" do
    sign_in_as(users(:one))

    get login_path(return_to: score_dashboard_path)

    assert_redirected_to score_dashboard_path
  end
end
