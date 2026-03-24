# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  class HillFunctionTest < ActiveSupport::TestCase
    # Hill: f(x) = K * x^S / (x^S + EC50^S)
    # With K=100, S=2, EC50=50:
    #   f(50) = 100 * 2500 / (2500 + 2500) = 50  (half-max by definition)
    #   f(0)  = 0
    #   f(∞)  → 100

    test "returns zero for zero spend" do
      assert_in_delta(0.0, HillFunction.evaluate(0, 100, 2, 50))
    end

    test "returns zero for negative spend" do
      assert_in_delta(0.0, HillFunction.evaluate(-10, 100, 2, 50))
    end

    test "returns half of K at EC50" do
      assert_in_delta 50.0, HillFunction.evaluate(50, 100, 2, 50), 0.01
    end

    test "approaches K at high spend" do
      assert_in_delta 100.0, HillFunction.evaluate(10_000, 100, 2, 50), 1.0
    end

    test "increases monotonically" do
      values = [ 10, 25, 50, 100, 200 ].map { |x| HillFunction.evaluate(x, 100, 2, 50) }

      assert_equal values, values.sort
    end

    # Derivative: mROAS(x) = K * S * EC50^S * x^(S-1) / (x^S + EC50^S)^2

    test "derivative returns nil for zero spend" do
      assert_nil HillFunction.derivative(0, 100, 2, 50)
    end

    test "derivative returns nil for negative spend" do
      assert_nil HillFunction.derivative(-5, 100, 2, 50)
    end

    test "derivative is positive at moderate spend" do
      result = HillFunction.derivative(50, 100, 2, 50)

      assert_predicate result, :positive?
    end

    test "derivative decreases as spend increases" do
      low = HillFunction.derivative(20, 100, 2, 50)
      high = HillFunction.derivative(200, 100, 2, 50)

      assert_operator low, :>, high
    end

    test "derivative diminishes at high spend" do
      moderate = HillFunction.derivative(50, 100, 2, 50)
      high = HillFunction.derivative(500, 100, 2, 50)

      assert_operator moderate, :>, high * 5
    end
  end
end
