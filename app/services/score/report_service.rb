# frozen_string_literal: true

module Score
  # Generates the full report data for a completed assessment.
  # Returns dimension analysis, business case, and roadmap.
  class ReportService
    include Score::ReportContent

    attr_reader :assessment

    def initialize(assessment)
      @assessment = assessment
    end

    def call
      {
        dimensions: dimension_analyses,
        business_case: business_case,
        roadmap: roadmap_for_level
      }
    end

    private

    def dimension_analyses
      Score::DIMENSIONS.each_with_object({}) do |dim, hash|
        score = assessment.dimension_scores.fetch(dim, Score::MIN_SCORE)
        level = Score.level_for_score(score)

        hash[dim] = {
          score: score,
          level: level,
          label: Score::DIMENSION_LABELS[dim],
          what_this_means: dimension_insight(dim, level),
          next_level: dimension_next_level(dim, level)
        }
      end
    end

    def business_case
      {
        ad_spend_bracket: spend_bracket,
        ad_spend_low: spend_range.first,
        ad_spend_high: spend_range.last,
        estimated_waste_low: estimated_waste_low,
        estimated_waste_high: estimated_waste_high,
        waste_pct_range: cfo_waste_pct,
        cfo_slide: cfo_slide
      }
    end

    def estimated_waste_low
      @estimated_waste_low ||= (spend_range.first * waste_range.first).round
    end

    def estimated_waste_high
      @estimated_waste_high ||= (spend_range.last * waste_range.last).round
    end

    def spend_bracket
      @spend_bracket ||= assessment.context&.dig("ad_spend") || "na"
    end

    def spend_range
      @spend_range ||= AD_SPEND_RANGES.fetch(spend_bracket, AD_SPEND_RANGES["na"])
    end

    def waste_range
      @waste_range ||= WASTE_BY_LEVEL.fetch(assessment.overall_level, [ 0.0, 0.0 ])
    end

    def cfo_slide
      "Our marketing measurement is at #{cfo_level_label}. " \
        "Peer-reviewed research suggests #{cfo_waste_pct} " \
        "of ad spend at this level is misallocated due to inaccurate attribution. " \
        "For our budget, that's an estimated #{cfo_waste_amount} annually."
    end

    def cfo_level_label
      "#{Score::LEVEL_NAMES[assessment.overall_level]} (Level #{assessment.overall_level})"
    end

    def cfo_waste_pct
      "#{(waste_range.first * 100).round}-#{(waste_range.last * 100).round}%"
    end

    def cfo_waste_amount
      "$#{format_number(estimated_waste_low)}-$#{format_number(estimated_waste_high)}"
    end

    def roadmap_for_level
      ROADMAPS.fetch(assessment.overall_level, ROADMAPS[Score::MAX_LEVEL])
    end

    def dimension_insight(dim, level)
      DIMENSION_INSIGHTS.dig(dim, level) || "No analysis available for this combination."
    end

    def dimension_next_level(dim, level)
      return "You're at the highest level for this dimension." if level >= Score::MAX_LEVEL

      DIMENSION_INSIGHTS.dig(dim, level + 1) || "Move to the next level by improving your #{Score::DIMENSION_LABELS[dim].downcase} capabilities."
    end

    def format_number(num)
      return "0" if num.zero?

      num >= 1_000 ? "#{(num / 1_000.0).round}K" : num.to_s
    end
  end
end
