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
        user: { email: "noclaimuser@example.com", password: "password123" }
      }
    end

    assert_redirected_to score_dashboard_path
  end
end
