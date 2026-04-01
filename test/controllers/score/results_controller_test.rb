# frozen_string_literal: true

require "test_helper"

class Score::ResultsControllerTest < ActionDispatch::IntegrationTest
  test "renders results page for a valid code" do
    code = Score.encode_answers([ 1, 2, 1, 2, 2, 2, 2, 1, 2, 2 ])

    get score_results_path(code: code)

    assert_response :success
  end

  test "passes decoded answers to the view as JSON" do
    answers = [ 1, 2, 1, 2, 2, 2, 2, 1, 2, 2 ]
    code = Score.encode_answers(answers)

    get score_results_path(code: code)

    assert_response :success
    assert_select "[data-score-results-answers-value]" do |elements|
      json = JSON.parse(elements.first["data-score-results-answers-value"])

      assert_equal answers, json
    end
  end

  test "returns 404 for invalid code" do
    get score_results_path(code: "ZZZZZZZZZZ")

    assert_response :not_found
  end

  test "returns 404 for code with invalid characters" do
    get score_results_path(code: "abc!@#")

    assert_response :not_found
  end

  test "returns 404 for code exceeding max permutations" do
    too_big = Score::TOTAL_PERMUTATIONS.to_s(Score::RESULT_CODE_BASE)

    get score_results_path(code: too_big)

    assert_response :not_found
  end

  test "all-zero code renders successfully" do
    code = Score.encode_answers([ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ])

    get score_results_path(code: code)

    assert_response :success
  end

  test "all-max code renders successfully" do
    code = Score.encode_answers([ 4, 4, 4, 4, 4, 4, 4, 4, 4, 4 ])

    get score_results_path(code: code)

    assert_response :success
  end

  test "does not create any database records" do
    code = Score.encode_answers([ 1, 2, 1, 2, 2, 2, 2, 1, 2, 2 ])

    assert_no_difference "ScoreAssessment.count" do
      get score_results_path(code: code)
    end
  end
end
