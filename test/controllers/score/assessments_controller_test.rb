# frozen_string_literal: true

require "test_helper"

class Score::AssessmentsControllerTest < ActionDispatch::IntegrationTest
  test "show renders the landing page" do
    get score_path

    assert_response :success
  end

  test "create persists an unclaimed assessment" do
    assert_difference "ScoreAssessment.count", 1 do
      post assessments_path, params: {
        assessment: {
          overall_score: 2.3,
          overall_level: 2,
          dimension_scores: { reporting: 2.5, attribution: 1.5, experimentation: 1.0, forecasting: 2.5, channels: 3.0, infrastructure: 2.0 },
          answers: [ { question_id: "q1", answer_id: "b", score: 1.5 } ],
          context: { company_size: "51-200", ad_spend: "100k-500k", role: "marketing" },
          source: "ppc_google",
          utm_params: { utm_source: "google", utm_medium: "cpc" },
          elapsed_ms: 120_000
        }
      }, as: :json
    end

    assert_response :created
  end

  test "create returns claim token and level for unclaimed assessment" do
    post assessments_path, params: {
      assessment: { overall_score: 2.3, overall_level: 2, dimension_scores: {}, answers: [], elapsed_ms: 60_000 }
    }, as: :json

    json = JSON.parse(response.body)

    assert_predicate json["claim_token"], :present?
    assert_equal 2, json["overall_level"]
    assert_equal "Operational", json["level_name"]
  end

  test "create for logged-in user links assessment to user" do
    sign_in_as(users(:one))

    post assessments_path, params: {
      assessment: {
        overall_score: 1.5,
        overall_level: 1,
        dimension_scores: { reporting: 1.5, attribution: 1.0 },
        answers: [ { question_id: "q1", answer_id: "a", score: 1.0 } ],
        elapsed_ms: 60_000
      }
    }, as: :json

    assert_response :created
    json = JSON.parse(response.body)

    assert_nil json["claim_token"]

    assessment = ScoreAssessment.last

    assert_equal users(:one).id, assessment.user_id
  end

  test "create rejects invalid data" do
    post assessments_path, params: {
      assessment: { overall_score: nil, overall_level: nil, elapsed_ms: 60_000 }
    }, as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)

    assert_predicate json["errors"], :present?
  end

  # ── Bot protection ──

  test "create rejects honeypot submissions" do
    assert_no_difference "ScoreAssessment.count" do
      post assessments_path, params: {
        assessment: { overall_score: 2.0, overall_level: 2, dimension_scores: {}, answers: [], elapsed_ms: 60_000 },
        website_url: "http://spam.example.com"
      }, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "create rejects submissions completed too fast" do
    assert_no_difference "ScoreAssessment.count" do
      post assessments_path, params: {
        assessment: { overall_score: 2.0, overall_level: 2, dimension_scores: {}, answers: [], elapsed_ms: 3_000 }
      }, as: :json
    end

    assert_response :unprocessable_entity
  end

  test "create allows submissions without elapsed_ms" do
    assert_difference "ScoreAssessment.count", 1 do
      post assessments_path, params: {
        assessment: { overall_score: 2.0, overall_level: 2, dimension_scores: {}, answers: [] }
      }, as: :json
    end

    assert_response :created
  end

  test "create rate limits excessive submissions from same IP" do
    params = { assessment: { overall_score: 2.0, overall_level: 2, dimension_scores: {}, answers: [], elapsed_ms: 60_000 } }

    Score::AssessmentsController::RATE_LIMIT.times do
      post assessments_path, params: params, as: :json

      assert_response :created
    end

    post assessments_path, params: params, as: :json

    assert_response :too_many_requests
  end

  test "claim links unclaimed assessment to newly logged-in user" do
    assessment = ScoreAssessment.create!(
      overall_score: 2.0,
      overall_level: 2,
      dimension_scores: {},
      answers: []
    )
    token = assessment.claim_token

    sign_in_as(users(:one))

    post claim_score_assessment_path, params: { claim_token: token }, as: :json

    assert_response :success
    assessment.reload

    assert_equal users(:one).id, assessment.user_id
    assert_nil assessment.claim_token
  end

  test "claim rejects invalid token" do
    sign_in_as(users(:one))

    post claim_score_assessment_path, params: { claim_token: "bogus" }, as: :json

    assert_response :not_found
  end

  test "claim requires authentication" do
    post claim_score_assessment_path, params: { claim_token: "anything" }, as: :json

    assert_response :unauthorized
  end
end
