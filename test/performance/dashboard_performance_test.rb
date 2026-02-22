# frozen_string_literal: true

require_relative "performance_test_helper"

class DashboardPerformanceTest < ActiveSupport::TestCase
  include PerformanceTestHelper

  # --- Timing budgets ---

  test "timing: TotalsQuery completes under 200ms" do
    avg_ms = measure_avg_ms(iterations: 20, warmup: 3) do
      Dashboard::Queries::TotalsQuery.new(credits_scope).call
    end

    assert_operator avg_ms, :<, 200, "TotalsQuery averaged #{avg_ms.round(1)}ms (budget: 200ms)"
  end

  test "timing: TimeSeriesQuery completes under 300ms" do
    avg_ms = measure_avg_ms(iterations: 20, warmup: 3) do
      Dashboard::Queries::TimeSeriesQuery.new(
        credits_scope,
        date_range: date_range
      ).call
    end

    assert_operator avg_ms, :<, 300, "TimeSeriesQuery averaged #{avg_ms.round(1)}ms (budget: 300ms)"
  end

  test "timing: ByChannelQuery completes under 200ms" do
    avg_ms = measure_avg_ms(iterations: 20, warmup: 3) do
      Dashboard::Queries::ByChannelQuery.new(credits_scope).call
    end

    assert_operator avg_ms, :<, 200, "ByChannelQuery averaged #{avg_ms.round(1)}ms (budget: 200ms)"
  end

  # --- Query budgets ---

  test "query budget: TotalsQuery queries are bounded" do
    queries = count_queries do
      Dashboard::Queries::TotalsQuery.new(credits_scope).call
    end

    assert_operator queries, :<=, 10, "TotalsQuery used #{queries} queries (budget: 10)"
  end

  test "query budget: ByChannelQuery queries are bounded" do
    queries = count_queries do
      Dashboard::Queries::ByChannelQuery.new(credits_scope).call
    end

    assert_operator queries, :<=, 10, "ByChannelQuery used #{queries} queries (budget: 10)"
  end

  private

  def credits_scope
    @credits_scope ||= account.attribution_credits.joins(:conversion)
  end

  def date_range
    @date_range ||= Dashboard::DateRangeParser.new("30d")
  end
end
