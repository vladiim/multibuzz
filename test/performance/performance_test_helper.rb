# frozen_string_literal: true

require "test_helper"
require "benchmark"
require "memory_profiler"

module PerformanceTestHelper
  private

  # Count SQL queries executed within block
  def count_queries(&block)
    counter = QueryCounter.new
    ActiveSupport::Notifications.subscribed(counter.method(:call), "sql.active_record", &block)
    counter.count
  end

  # Assert block executes within query budget
  def assert_query_budget(max_queries, message = nil, &block)
    actual = count_queries(&block)
    msg = message || "Expected <= #{max_queries} queries, got #{actual}"

    assert_operator actual, :<=, max_queries, msg
  end

  # Measure average execution time over N iterations (with warmup)
  def measure_avg_ms(iterations: 50, warmup: 5, &block)
    warmup.times { block.call }

    elapsed = Benchmark.realtime do
      iterations.times { block.call }
    end

    (elapsed / iterations) * 1000
  end

  # Measure object allocations within block
  def measure_allocations(&block)
    block.call # warmup

    report = MemoryProfiler.report(&block)
    report.total_allocated
  end

  # Auth helpers for API tests
  def auth_headers
    { "Authorization" => "Bearer #{plaintext_key}" }
  end

  def plaintext_key
    @plaintext_key ||= begin
      key = "sk_test_#{SecureRandom.hex(16)}"
      api_key.update_column(:key_digest, Digest::SHA256.hexdigest(key))
      key
    end
  end

  def api_key
    @api_key ||= api_keys(:one)
  end

  def account
    @account ||= accounts(:one)
  end

  class QueryCounter
    attr_reader :count

    def initialize
      @count = 0
    end

    def call(_name, _start, _finish, _id, payload)
      @count += 1 unless payload[:name]&.match?(/SCHEMA|TRANSACTION/)
    end
  end
end
