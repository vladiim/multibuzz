# frozen_string_literal: true

require_relative "performance_test_helper"

class AttributionPerformanceTest < ActiveSupport::TestCase
  include PerformanceTestHelper

  # --- Timing budgets ---

  test "timing: calculator with fixture journey completes under 100ms" do
    avg_ms = measure_avg_ms(iterations: 20, warmup: 3) do
      calculator.call
    end

    assert_operator avg_ms, :<, 100, "Calculator averaged #{avg_ms.round(1)}ms (budget: 100ms)"
  end

  test "timing: cross-device calculator completes under 100ms" do
    avg_ms = measure_avg_ms(iterations: 20, warmup: 3) do
      cross_device_calculator.call
    end

    assert_operator avg_ms, :<, 100, "CrossDeviceCalculator averaged #{avg_ms.round(1)}ms (budget: 100ms)"
  end

  # --- Query budgets ---

  test "query budget: calculator queries are bounded" do
    queries = count_queries { calculator.call }

    assert_operator queries, :<=, 10, "Calculator used #{queries} queries (budget: 10)"
  end

  test "query budget: cross-device calculator queries are bounded" do
    queries = count_queries { cross_device_calculator.call }

    assert_operator queries, :<=, 15, "CrossDeviceCalculator used #{queries} queries (budget: 15)"
  end

  # --- Memory budgets ---

  test "memory: calculator allocates bounded objects" do
    allocations = measure_allocations { calculator.call }

    assert_operator allocations, :<, 5_000, "Calculator allocated #{allocations} objects (budget: 5,000)"
  end

  private

  def calculator
    Attribution::Calculator.new(
      conversion: conversion,
      attribution_model: attribution_model
    )
  end

  def cross_device_calculator
    Attribution::CrossDeviceCalculator.new(
      conversion: conversion,
      identity: identity,
      attribution_model: attribution_model
    )
  end

  def conversion
    @conversion ||= conversions(:signup)
  end

  def identity
    @identity ||= identities(:one)
  end

  def attribution_model
    @attribution_model ||= attribution_models(:first_touch)
  end
end
