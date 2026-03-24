# frozen_string_literal: true

module SpendIntelligence
  class HillBootstrap
    ITERATIONS = 100
    MIN_ESTIMATES = 10
    MIN_LINEARIZABLE = HillFit::MIN_LINEARIZABLE
    MIN_S = HillFit::MIN_S
    LOWER_PERCENTILE = 0.1
    UPPER_PERCENTILE = 0.9
    SEED = 42

    Result = Data.define(:low, :high)

    def initialize(weeks:, k:)
      @weeks = weeks
      @k = k
      @rng = Random.new(SEED)
    end

    def call
      sufficient_estimates? ? bounded_result : empty_result
    end

    private

    attr_reader :weeks, :k, :rng

    def sufficient_estimates? = sorted_estimates.size >= MIN_ESTIMATES
    def bounded_result = Result.new(low: lower_bound, high: upper_bound)
    def empty_result = Result.new(low: nil, high: nil)

    def lower_bound = sorted_estimates[(sorted_estimates.size * LOWER_PERCENTILE).to_i]
    def upper_bound = sorted_estimates[(sorted_estimates.size * UPPER_PERCENTILE).to_i]

    def sorted_estimates
      @sorted_estimates ||= ITERATIONS.times.filter_map(&method(:estimate_ec50)).sort
    end

    def estimate_ec50(_iteration)
      regression_for(linearize(resample))&.then(&method(:ec50_from))
    end

    def ec50_from(regression)
      [ -regression.slope, MIN_S ].max
        .then { |s| Math.exp(regression.intercept / s) }
    end

    def regression_for(points)
      return nil if points.size < MIN_LINEARIZABLE

      LinearRegression.new(points)
    end

    def resample
      weeks.size.times.map { weeks[rng.rand(weeks.size)] }
    end

    def linearize(sample)
      sample
        .select(&method(:linearizable?))
        .map(&method(:to_log_coordinates))
    end

    def linearizable?(week)
      week[:spend].positive? && week[:revenue].positive? && week[:revenue] < k
    end

    def to_log_coordinates(week)
      [ Math.log(week[:spend]), Math.log(k / week[:revenue] - 1) ]
    end
  end
end
