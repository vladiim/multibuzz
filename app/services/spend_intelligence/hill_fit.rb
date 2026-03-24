# frozen_string_literal: true

module SpendIntelligence
  class HillFit
    MIN_LINEARIZABLE = 3
    MIN_S = 0.1
    K_HEADROOM = 1.3
    ZERO_VARIANCE = 0.0

    def initialize(weeks)
      @weeks = weeks
    end

    def call
      return empty_result unless fittable?

      {
        k: k.round(2),
        s: s.round(4),
        ec50: ec50.round(2),
        r_squared: r_squared.round(4),
        confidence_low: confidence.low&.round(2),
        confidence_high: confidence.high&.round(2),
        weeks: weeks.size
      }
    end

    private

    attr_reader :weeks

    def fittable? = linearized_points.size >= MIN_LINEARIZABLE

    # --- Hill Parameters ---

    def k = @k ||= revenues.max * K_HEADROOM
    def s = @s ||= [ -regression.slope, MIN_S ].max
    def ec50 = @ec50 ||= Math.exp(regression.intercept / s)
    def regression = @regression ||= LinearRegression.new(linearized_points)
    def revenues = @revenues ||= weeks.map(&method(:revenue_for))

    # --- Linearization: ln(K/y - 1) = -S·ln(x) + S·ln(EC50) ---

    def linearized_points
      @linearized_points ||= linearizable_weeks.map(&method(:linearize))
    end

    def linearizable_weeks
      weeks.select(&method(:linearizable?))
    end

    def linearizable?(week)
      week[:spend].positive? && week[:revenue].positive? && week[:revenue] < k
    end

    def linearize(week)
      [ Math.log(week[:spend]), Math.log(k / week[:revenue] - 1) ]
    end

    def revenue_for(week) = week[:revenue]

    # --- Goodness of Fit ---

    def r_squared
      @r_squared ||= total_variance.zero? ? ZERO_VARIANCE : 1 - residual_variance / total_variance
    end

    def residual_variance
      @residual_variance ||= weeks.sum(&method(:squared_residual))
    end

    def total_variance
      @total_variance ||= revenues.sum(&method(:squared_deviation))
    end

    def squared_residual(week)
      (week[:revenue] - predicted_revenue(week[:spend]))**2
    end

    def squared_deviation(revenue)
      (revenue - mean_revenue)**2
    end

    def predicted_revenue(spend) = HillFunction.evaluate(spend, k, s, ec50)
    def mean_revenue = @mean_revenue ||= revenues.sum / revenues.size.to_f

    # --- Confidence ---

    def confidence = @confidence ||= HillBootstrap.new(weeks: weeks, k: k).call

    def empty_result
      {
        k: nil,
        s: nil,
        ec50: nil,
        r_squared: nil,
        confidence_low: nil,
        confidence_high: nil,
        weeks: 0
      }
    end
  end
end
