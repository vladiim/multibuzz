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

  def self.level_for_score(score)
    LEVEL_THRESHOLDS.find { |_, range| range.cover?(score) }&.first || MIN_LEVEL
  end
end
