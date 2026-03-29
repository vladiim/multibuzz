# frozen_string_literal: true

module Score
  # Calculates team alignment as a 0-100 score based on how closely
  # team members' assessment scores agree.
  #
  # 100 = perfect agreement (everyone scored identically)
  # 0   = maximum disagreement
  #
  # Uses normalised standard deviation against the theoretical max
  # spread for the score range.
  class AlignmentCalculator
    attr_reader :scores

    def initialize(scores)
      @scores = scores
    end

    def call
      return nil if scores.size < Score::TEAM_UNLOCK_THRESHOLD

      capped = [ normalized_deviation, Score::MIN_SCORE ].min
      ((Score::MIN_SCORE - capped) * Score::ALIGNMENT_PERFECT).round(1)
    end

    private

    def normalized_deviation
      @normalized_deviation ||= std_deviation / Score::ALIGNMENT_MAX_STD_DEV
    end

    def std_deviation
      @std_deviation ||= Math.sqrt(variance)
    end

    def variance
      @variance ||= scores.sum { |s| (s - mean)**2 } / scores.size.to_f
    end

    def mean
      @mean ||= scores.sum / scores.size.to_f
    end
  end
end
