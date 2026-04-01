# frozen_string_literal: true

require "test_helper"

class Score::SignupControllerTest < ActionDispatch::IntegrationTest
  test "new renders signup form" do
    get score_signup_path

    assert_response :success
  end

  test "create with valid params creates account and logs in" do
    assessment = ScoreAssessment.create!(overall_score: 2.0, overall_level: 2)
    token = assessment.claim_token

    post score_signup_path, params: {
      user: { email: "newscore@example.com", password: "password123" },
      claim_token: token
    }

    assert_redirected_to score_dashboard_path

    assessment.reload

    assert_equal "newscore@example.com", User.find(assessment.user_id).email
  end

  test "create with invalid params re-renders form" do
    post score_signup_path, params: {
      user: { email: "", password: "" }
    }

    assert_response :unprocessable_entity
  end

  test "create without claim token still works" do
    assert_difference "User.count", 1 do
      post score_signup_path, params: {
        user: { email: "noclaimuser@example.com", password: "password123", company_name: "Acme Corp" }
      }
    end

    assert_redirected_to score_dashboard_path
  end

  test "create uses company_name as account name" do
    post score_signup_path, params: {
      user: { email: "acme@example.com", password: "password123", company_name: "Acme Corp" }
    }

    assert_redirected_to score_dashboard_path
    account = User.find_by(email: "acme@example.com").account_memberships.first.account

    assert_equal "Acme Corp", account.name
  end

  test "create falls back to email domain when company_name is blank" do
    post score_signup_path, params: {
      user: { email: "fallback@widgetco.com", password: "password123", company_name: "" }
    }

    assert_redirected_to score_dashboard_path
    account = User.find_by(email: "fallback@widgetco.com").account_memberships.first.account

    assert_equal "widgetco.com", account.name
  end

  test "signup form includes company name field" do
    get score_signup_path

    assert_response :success
    assert_select "input[name='user[company_name]']"
  end

  test "create with invalid params preserves company name in form" do
    post score_signup_path, params: {
      user: { email: "", password: "", company_name: "Acme Corp" }
    }

    assert_response :unprocessable_entity
    assert_select "input[name='user[company_name]'][value='Acme Corp']"
  end

  test "logged-in user visiting signup is redirected to score dashboard" do
    sign_in_as(users(:one))

    get score_signup_path

    assert_redirected_to score_dashboard_path
  end

  test "logged-in user posting to signup is redirected to score dashboard" do
    sign_in_as(users(:one))

    post score_signup_path, params: {
      user: { email: "new@example.com", password: "password123", company_name: "Test" }
    }

    assert_redirected_to score_dashboard_path
  end
end
