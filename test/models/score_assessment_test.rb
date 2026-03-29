# frozen_string_literal: true

require "test_helper"

class ScoreAssessmentTest < ActiveSupport::TestCase
  test "valid assessment with all required fields" do
    assessment = ScoreAssessment.new(
      overall_score: 2.3,
      overall_level: 2,
      dimension_scores: { reporting: 2.5, attribution: 1.5, experimentation: 1.0, forecasting: 2.5, channels: 3.0, infrastructure: 2.0 },
      answers: [ { question_id: "q1", answer_id: "b", score: 1.5 } ]
    )

    assert_predicate assessment, :valid?
  end

  test "requires overall_score" do
    assessment = ScoreAssessment.new(overall_level: 2)

    assert_not assessment.valid?
    assert_includes assessment.errors[:overall_score], "can't be blank"
  end

  test "requires overall_level" do
    assessment = ScoreAssessment.new(overall_score: 2.3)

    assert_not assessment.valid?
    assert_includes assessment.errors[:overall_level], "can't be blank"
  end

  test "overall_level must be between 1 and 4" do
    assessment = ScoreAssessment.new(overall_score: 2.3, overall_level: 0)

    assert_not assessment.valid?

    assessment.overall_level = 5

    assert_not assessment.valid?

    assessment.overall_level = 2

    assert_predicate assessment, :valid?
  end

  test "overall_score must be between 1.0 and 4.0" do
    assessment = ScoreAssessment.new(overall_level: 2, overall_score: 0.5)

    assert_not assessment.valid?

    assessment.overall_score = 4.5

    assert_not assessment.valid?

    assessment.overall_score = 2.3

    assert_predicate assessment, :valid?
  end

  test "can belong to a user" do
    assessment = ScoreAssessment.new(
      overall_score: 2.3,
      overall_level: 2,
      user: users(:one)
    )

    assert_predicate assessment, :valid?
    assert_equal users(:one), assessment.user
  end

  test "can exist without a user (unclaimed)" do
    assessment = ScoreAssessment.new(
      overall_score: 1.5,
      overall_level: 1
    )

    assert_predicate assessment, :valid?
    assert_nil assessment.user
  end

  test "claimed? returns true when user is present" do
    assessment = ScoreAssessment.new(user: users(:one), overall_score: 2.0, overall_level: 2)

    assert_predicate assessment, :claimed?
  end

  test "claimed? returns false when user is nil" do
    assessment = ScoreAssessment.new(overall_score: 2.0, overall_level: 2)

    assert_not assessment.claimed?
  end

  test "generates claim_token on create when no user" do
    assessment = ScoreAssessment.create!(overall_score: 2.0, overall_level: 2)

    assert_not_nil assessment.claim_token
  end

  test "does not generate claim_token when user is present" do
    assessment = ScoreAssessment.create!(overall_score: 2.0, overall_level: 2, user: users(:one))

    assert_nil assessment.claim_token
  end

  Score::LEVEL_NAMES.each do |level, name|
    test "level_name returns #{name} for level #{level}" do
      assert_equal name, ScoreAssessment.new(overall_level: level).level_name
    end
  end

  test "strongest_dimension returns highest scoring dimension" do
    assessment = ScoreAssessment.new(
      overall_score: 2.0,
      overall_level: 2,
      dimension_scores: { "reporting" => 3.0, "attribution" => 1.5, "experimentation" => 1.0 }
    )

    assert_equal "reporting", assessment.strongest_dimension
  end

  test "weakest_dimension returns lowest scoring dimension" do
    assessment = ScoreAssessment.new(
      overall_score: 2.0,
      overall_level: 2,
      dimension_scores: { "reporting" => 3.0, "attribution" => 1.5, "experimentation" => 1.0 }
    )

    assert_equal "experimentation", assessment.weakest_dimension
  end
end
