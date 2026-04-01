# frozen_string_literal: true

# Constants for the Measurement Maturity Score assessment tool
module Score
  MIN_LEVEL = 1
  MAX_LEVEL = 4
  MIN_SCORE = 1.0
  MAX_SCORE = 4.0

  # Score → level mapping thresholds
  LEVEL_THRESHOLDS = {
    1 => 0.0..1.7,
    2 => 1.8..2.4,
    3 => 2.5..3.2,
    4 => 3.3..MAX_SCORE
  }.freeze

  LEVEL_NAMES = {
    1 => "Ad Hoc",
    2 => "Operational",
    3 => "Analytical",
    4 => "Leader"
  }.freeze

  DIMENSION_LABELS = {
    "reporting" => "Reporting & Analytics",
    "attribution" => "Attribution & Credit",
    "experimentation" => "Experimentation",
    "forecasting" => "Forecasting & Optimisation",
    "channels" => "Channel Coverage",
    "infrastructure" => "Data Infrastructure"
  }.freeze

  DIMENSIONS = DIMENSION_LABELS.keys.freeze

  # Team dashboard unlocks at this many members
  TEAM_UNLOCK_THRESHOLD = 3

  # Retake allowed after this many days
  RETAKE_INTERVAL_DAYS = 90

  # Alignment score calculation
  # Max possible std deviation for scores in 1.0-4.0 range
  ALIGNMENT_MAX_STD_DEV = 1.5
  ALIGNMENT_PERFECT = 100.0

  # Questions weighted higher in scoring
  WEIGHTED_QUESTION_IDS = %w[q2 q10].freeze
  WEIGHTED_QUESTION_MULTIPLIER = 1.5

  # Shareable result codes — encode 10 answers (each 0-4) as base36
  QUESTION_COUNT = 10
  ANSWERS_PER_QUESTION = 5
  TOTAL_PERMUTATIONS = ANSWERS_PER_QUESTION**QUESTION_COUNT # 9,765,625
  RESULT_CODE_BASE = 36

  def self.level_for_score(score)
    LEVEL_THRESHOLDS.find { |_, range| range.cover?(score) }&.first || MIN_LEVEL
  end

  # Encode an array of 10 answer indices (each 0..4) into a base36 string
  def self.encode_answers(answers)
    return nil unless answers.is_a?(Array) && answers.length == QUESTION_COUNT
    return nil unless answers.all? { |a| a.is_a?(Integer) && a >= 0 && a < ANSWERS_PER_QUESTION }

    num = answers.reduce(0) { |acc, a| acc * ANSWERS_PER_QUESTION + a }
    num.to_s(RESULT_CODE_BASE)
  end

  # Decode a base36 string back to 10 answer indices (each 0..4)
  def self.decode_answers(code)
    return nil unless code.is_a?(String) && code.match?(/\A[0-9a-z]+\z/)

    num = code.to_i(RESULT_CODE_BASE)
    return nil if num >= TOTAL_PERMUTATIONS

    answers = []
    QUESTION_COUNT.times do
      answers.unshift(num % ANSWERS_PER_QUESTION)
      num /= ANSWERS_PER_QUESTION
    end

    answers
  rescue ArgumentError
    nil
  end
end
