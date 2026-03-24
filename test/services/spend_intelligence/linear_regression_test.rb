# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  class LinearRegressionTest < ActiveSupport::TestCase
    # y = 2x + 1 → slope=2, intercept=1
    test "fits perfect linear data" do
      reg = LinearRegression.new([ [ 1.0, 3.0 ], [ 2.0, 5.0 ], [ 3.0, 7.0 ], [ 4.0, 9.0 ] ])

      assert_in_delta 2.0, reg.slope, 0.001
      assert_in_delta 1.0, reg.intercept, 0.001
    end

    # y = -0.5x + 10
    test "fits negative slope" do
      reg = LinearRegression.new([ [ 0.0, 10.0 ], [ 4.0, 8.0 ], [ 8.0, 6.0 ], [ 12.0, 4.0 ] ])

      assert_in_delta(-0.5, reg.slope, 0.001)
      assert_in_delta 10.0, reg.intercept, 0.001
    end

    test "returns zero slope and intercept for insufficient points" do
      reg = LinearRegression.new([ [ 1.0, 1.0 ] ])

      assert_equal 0, reg.slope
      assert_equal 0, reg.intercept
    end

    test "returns zero slope for constant y" do
      reg = LinearRegression.new([ [ 1.0, 5.0 ], [ 2.0, 5.0 ], [ 3.0, 5.0 ] ])

      assert_in_delta 0.0, reg.slope, 0.001
    end

    test "handles noisy data" do
      reg = LinearRegression.new([ [ 1.0, 2.1 ], [ 2.0, 4.2 ], [ 3.0, 5.8 ], [ 4.0, 8.1 ], [ 5.0, 9.9 ] ])

      assert_in_delta 2.0, reg.slope, 0.1
      assert_in_delta 0.0, reg.intercept, 0.5
    end
  end
end
