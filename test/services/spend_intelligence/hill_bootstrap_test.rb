# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  class HillBootstrapTest < ActiveSupport::TestCase
    test "returns Result with low and high for sufficient data" do
      result = bootstrap.call

      assert_kind_of HillBootstrap::Result, result
      assert_kind_of Numeric, result.low
      assert_kind_of Numeric, result.high
    end

    test "low is less than high" do
      result = bootstrap.call

      assert_operator result.low, :<, result.high
    end

    test "returns nil bounds for insufficient data" do
      result = HillBootstrap.new(weeks: few_weeks, k: 100.0).call

      assert_nil result.low
      assert_nil result.high
    end

    test "is deterministic with fixed seed" do
      a = bootstrap.call
      b = bootstrap.call

      assert_equal a.low, b.low
      assert_equal a.high, b.high
    end

    private

    def bootstrap
      HillBootstrap.new(weeks: synthetic_weeks, k: 1300.0)
    end

    def synthetic_weeks
      @synthetic_weeks ||= (1..20).map do |i|
        spend = i * 100.0
        revenue = HillFunction.evaluate(spend, 1000, 1.5, 500) * (0.9 + 0.1 * (i % 3))
        {
          week: Date.new(2026, 1, 1) + (i * 7),
          spend: spend,
          revenue: revenue
        }
      end
    end

    def few_weeks
      synthetic_weeks.first(2)
    end
  end
end
