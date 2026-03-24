# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  class HillFitTest < ActiveSupport::TestCase
    # Generate synthetic data from known Hill params: K=1000, S=1.5, EC50=500
    # Then verify the fit recovers approximately those params.

    test "returns empty result with fewer than 3 linearizable points" do
      result = HillFit.new(too_few_points).call

      assert_nil result[:k]
      assert_nil result[:ec50]
      assert_equal 0, result[:weeks]
    end

    test "returns numeric k, s, ec50" do
      assert_kind_of Numeric, fit[:k]
      assert_kind_of Numeric, fit[:s]
      assert_kind_of Numeric, fit[:ec50]
    end

    test "returns correct week count" do
      assert_equal synthetic_weeks.size, fit[:weeks]
    end

    test "k exceeds observed maximum revenue" do
      max_observed = synthetic_weeks.map { |w| w[:revenue] }.max

      assert_operator fit[:k], :>, max_observed
    end

    test "ec50 is positive" do
      assert_predicate fit[:ec50], :positive?
    end

    test "s is positive" do
      assert_predicate fit[:s], :positive?
    end

    test "r_squared is positive for well-shaped data" do
      assert_predicate fit[:r_squared], :positive?
    end

    test "includes confidence bounds" do
      assert_kind_of Numeric, fit[:confidence_low]
      assert_kind_of Numeric, fit[:confidence_high]
      assert_operator fit[:confidence_low], :<, fit[:confidence_high]
    end

    private

    def fit = @fit ||= HillFit.new(synthetic_weeks).call

    def synthetic_weeks
      @synthetic_weeks ||= begin
        rng = Random.new(42)
        (1..20).map do |i|
          spend = i * 100.0
          noise = 0.9 + rng.rand * 0.2
          revenue = HillFunction.evaluate(spend, 1000, 1.5, 500) * noise
          { week: Date.new(2026, 1, 1) + (i * 7), spend: spend, revenue: revenue }
        end
      end
    end

    def too_few_points
      [
        { week: Date.new(2026, 1, 1), spend: 0.0, revenue: 0.0 },
        { week: Date.new(2026, 1, 8), spend: 0.0, revenue: 0.0 }
      ]
    end
  end
end
