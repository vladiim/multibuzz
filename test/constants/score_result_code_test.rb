# frozen_string_literal: true

require "test_helper"

class ScoreResultCodeTest < ActiveSupport::TestCase
  # ── encode_answers ──

  test "encodes 10 answer indices into a base36 string" do
    answers = [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ]
    code = Score.encode_answers(answers)

    assert_equal "0", code
  end

  test "encodes all-max answers to a valid code" do
    answers = [ 4, 4, 4, 4, 4, 4, 4, 4, 4, 4 ]
    code = Score.encode_answers(answers)

    assert_predicate code, :present?
    assert_operator code.to_i(Score::RESULT_CODE_BASE), :<, Score::TOTAL_PERMUTATIONS
  end

  test "encodes a mixed answer set" do
    answers = [ 1, 2, 1, 2, 2, 2, 2, 1, 2, 2 ]
    code = Score.encode_answers(answers)

    assert_predicate code, :present?
  end

  test "returns nil for wrong number of answers" do
    assert_nil Score.encode_answers([ 0, 0, 0 ])
    assert_nil Score.encode_answers([ 0 ] * 11)
  end

  test "returns nil for out-of-range answer index" do
    assert_nil Score.encode_answers([ 0, 0, 0, 0, 0, 0, 0, 0, 0, 5 ])
    assert_nil Score.encode_answers([ 0, 0, 0, 0, 0, 0, 0, 0, 0, -1 ])
  end

  test "returns nil for non-integer answers" do
    assert_nil Score.encode_answers([ "a", "b", "c", "d", "e", "a", "b", "c", "d", "e" ])
  end

  test "returns nil for non-array input" do
    assert_nil Score.encode_answers("hello")
    assert_nil Score.encode_answers(nil)
  end

  # ── decode_answers ──

  test "decodes a base36 string back to 10 answer indices" do
    code = Score.encode_answers([ 1, 2, 1, 2, 2, 2, 2, 1, 2, 2 ])
    answers = Score.decode_answers(code)

    assert_equal [ 1, 2, 1, 2, 2, 2, 2, 1, 2, 2 ], answers
  end

  test "decodes all-zero code" do
    answers = Score.decode_answers("0")

    assert_equal [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ], answers
  end

  test "roundtrips every edge case" do
    [ [ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 ],
     [ 4, 4, 4, 4, 4, 4, 4, 4, 4, 4 ],
     [ 0, 1, 2, 3, 4, 0, 1, 2, 3, 4 ],
     [ 4, 3, 2, 1, 0, 4, 3, 2, 1, 0 ] ].each do |answers|
      code = Score.encode_answers(answers)
      decoded = Score.decode_answers(code)

      assert_equal answers, decoded, "Roundtrip failed for #{answers.inspect}"
    end
  end

  test "returns nil for code exceeding total permutations" do
    too_big = Score::TOTAL_PERMUTATIONS.to_s(Score::RESULT_CODE_BASE)

    assert_nil Score.decode_answers(too_big)
  end

  test "returns nil for non-alphanumeric code" do
    assert_nil Score.decode_answers("abc!@#")
    assert_nil Score.decode_answers("ABC")
  end

  test "returns nil for nil input" do
    assert_nil Score.decode_answers(nil)
  end

  test "returns nil for empty string" do
    assert_nil Score.decode_answers("")
  end

  # ── Constants ──

  test "total permutations is 5^10" do
    assert_equal 5**10, Score::TOTAL_PERMUTATIONS
    assert_equal 9_765_625, Score::TOTAL_PERMUTATIONS
  end
end
