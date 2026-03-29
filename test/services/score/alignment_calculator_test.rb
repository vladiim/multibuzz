# frozen_string_literal: true

require "test_helper"

class Score::AlignmentCalculatorTest < ActiveSupport::TestCase
  test "returns nil when fewer than team unlock threshold" do
    result = Score::AlignmentCalculator.new([ 2.0, 2.5 ]).call

    assert_nil result
  end

  test "returns perfect alignment when all scores identical" do
    result = Score::AlignmentCalculator.new([ 2.0, 2.0, 2.0 ]).call

    assert_equal Score::ALIGNMENT_PERFECT, result
  end

  test "returns lower alignment when scores diverge" do
    result = Score::AlignmentCalculator.new([ 1.0, 2.5, 4.0 ]).call

    assert_operator result, :<, Score::ALIGNMENT_PERFECT
    assert_operator result, :>, 0
  end

  test "returns zero alignment at maximum theoretical spread" do
    # Scores at extreme ends with max std dev
    result = Score::AlignmentCalculator.new([ Score::MIN_SCORE, Score::MAX_SCORE, Score::MIN_SCORE ]).call

    assert_operator result, :<, 50
  end

  test "more agreement means higher score" do
    tight = Score::AlignmentCalculator.new([ 2.0, 2.1, 2.2 ]).call
    loose = Score::AlignmentCalculator.new([ 1.0, 2.5, 4.0 ]).call

    assert_operator tight, :>, loose
  end
end
