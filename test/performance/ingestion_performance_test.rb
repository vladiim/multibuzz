# frozen_string_literal: true

require_relative "performance_test_helper"

class IngestionPerformanceTest < ActionDispatch::IntegrationTest
  include PerformanceTestHelper

  # --- Timing budgets ---

  test "timing: session creation completes under 50ms average" do
    avg_ms = measure_avg_ms(iterations: 20, warmup: 3) do
      post api_v1_sessions_path, params: session_payload, headers: auth_headers, as: :json
    end

    assert_operator avg_ms, :<, 50, "Session creation averaged #{avg_ms.round(1)}ms (budget: 50ms)"
  end

  test "timing: event batch scales sub-linearly" do
    # Warmup
    3.times { post_events(count: 1) }

    time_1 = Benchmark.realtime { post_events(count: 1) }
    time_10 = Benchmark.realtime { post_events(count: 10) }

    ratio = time_10 / [ time_1, 0.001 ].max

    assert_operator ratio, :<, 8.0, "10 events took #{ratio.round(1)}x single event (budget: 8x)"
  end

  test "timing: conversion tracking completes under 75ms average" do
    avg_ms = measure_avg_ms(iterations: 20, warmup: 3) do
      post api_v1_conversions_path, params: conversion_payload, headers: auth_headers, as: :json
    end

    assert_operator avg_ms, :<, 75, "Conversion tracking averaged #{avg_ms.round(1)}ms (budget: 75ms)"
  end

  test "timing: identify completes under 30ms average" do
    avg_ms = measure_avg_ms(iterations: 20, warmup: 3) do
      post api_v1_identify_path, params: identify_payload, headers: auth_headers, as: :json
    end

    assert_operator avg_ms, :<, 30, "Identify averaged #{avg_ms.round(1)}ms (budget: 30ms)"
  end

  # --- Query budgets ---

  test "query budget: session creation stays within budget" do
    queries = count_queries do
      post api_v1_sessions_path, params: session_payload, headers: auth_headers, as: :json
    end

    assert_operator queries, :<=, 20, "Session creation used #{queries} queries (budget: 20)"
  end

  test "query budget: event batch queries do not scale linearly" do
    queries_1 = count_queries { post_events(count: 1) }
    queries_10 = count_queries { post_events(count: 10) }

    ratio = queries_10.to_f / [ queries_1, 1 ].max

    assert_operator ratio, :<, 5.0, "10 events used #{queries_10} queries vs #{queries_1} for 1 (#{ratio.round(1)}x, budget: 5x)"
  end

  # --- Memory budgets ---

  test "memory: session creation allocates bounded objects" do
    allocations = measure_allocations do
      post api_v1_sessions_path, params: session_payload, headers: auth_headers, as: :json
    end

    assert_operator allocations, :<, 8_000, "Session creation allocated #{allocations} objects (budget: 8,000)"
  end

  test "memory: event batch does not allocate linearly" do
    alloc_1 = measure_allocations { post_events(count: 1) }
    alloc_10 = measure_allocations { post_events(count: 10) }

    ratio = alloc_10.to_f / [ alloc_1, 1 ].max

    assert_operator ratio, :<, 8.0, "10 events allocated #{ratio.round(1)}x single event (budget: 8x)"
  end

  private

  def session_payload
    {
      session: {
        visitor_id: SecureRandom.hex(32),
        session_id: SecureRandom.hex(32),
        url: "https://example.com/landing?utm_source=google&utm_medium=cpc"
      }
    }
  end

  def post_events(count:)
    events = count.times.map do
      {
        event_type: "page_view",
        visitor_id: visitors(:one).visitor_id,
        session_id: sessions(:one).session_id,
        timestamp: Time.current.iso8601,
        properties: { url: "https://example.com/page/#{SecureRandom.hex(4)}" }
      }
    end

    post api_v1_events_path, params: { events: events }, headers: auth_headers, as: :json
  end

  def conversion_payload
    {
      conversion: {
        visitor_id: visitors(:one).visitor_id,
        conversion_type: "purchase_#{SecureRandom.hex(4)}",
        revenue: 49.99,
        idempotency_key: SecureRandom.uuid
      }
    }
  end

  def identify_payload
    {
      identify: {
        visitor_id: visitors(:one).visitor_id,
        user_id: "user_#{SecureRandom.hex(8)}",
        traits: { email: "perf@example.com" }
      }
    }
  end

  def visitor
    @visitor ||= visitors(:one)
  end
end
