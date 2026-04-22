# frozen_string_literal: true

require "test_helper"

module Infrastructure
  class QueueDepthAlertTest < ActiveSupport::TestCase
    setup do
      @reports = [] # rubocop:disable ThreadSafety/MutableClassInstanceVariable
      @subscriber = TestErrorSubscriber.new { |error, ctx| @reports << [ error.message, ctx ] }
      Rails.error.subscribe(@subscriber)
    end

    teardown do
      Rails.error.unsubscribe(@subscriber)
    end

    # rubocop:disable Minitest/MultipleAssertions
    test "thresholds expose tunable defaults" do
      assert_equal 200, QueueDepthAlert::DEFAULT_READY_THRESHOLD
      assert_equal 30.minutes, QueueDepthAlert::DEFAULT_STUCK_DURATION
      assert_equal 10, QueueDepthAlert::DEFAULT_RECENT_FAILURE_THRESHOLD
      assert_equal 1.hour, QueueDepthAlert::DEFAULT_RECENT_FAILURE_WINDOW
    end
    # rubocop:enable Minitest/MultipleAssertions

    test "no-ops when queue is healthy" do
      QueueDepthAlert.new(metrics: metrics(ready: 0, stuck: 0, recent_failures: 0)).call

      assert_empty @reports
    end

    # rubocop:disable Minitest/MultipleAssertions
    test "reports elevated ready depth when count exceeds threshold" do
      QueueDepthAlert.new(
        ready_threshold: 2,
        metrics: metrics(ready: 3, ready_breakdown: { "FooJob" => 2, "BarJob" => 1 })
      ).call

      message, ctx = find_report("ready depth")

      refute_nil message
      assert_equal 3, ctx[:ready_count]
      assert_equal 2, ctx[:threshold]
      assert_equal({ "FooJob" => 2, "BarJob" => 1 }, ctx[:breakdown])
    end
    # rubocop:enable Minitest/MultipleAssertions

    test "does not report ready depth when count is at or below threshold" do
      QueueDepthAlert.new(ready_threshold: 2, metrics: metrics(ready: 2)).call

      assert_nil find_report("ready depth").first
    end

    # rubocop:disable Minitest/MultipleAssertions
    test "reports stuck jobs when any claim is older than stuck_duration" do
      QueueDepthAlert.new(
        metrics: metrics(stuck: 3, oldest_stuck_age_minutes: 45, stuck_breakdown: { "SomeJob" => 3 })
      ).call

      message, ctx = find_report("stuck")

      refute_nil message
      assert_equal 3, ctx[:stuck_count]
      assert_equal 45, ctx[:oldest_age_minutes]
      assert_equal({ "SomeJob" => 3 }, ctx[:breakdown])
    end
    # rubocop:enable Minitest/MultipleAssertions

    test "does not report stuck jobs when none are stuck" do
      QueueDepthAlert.new(metrics: metrics(stuck: 0)).call

      assert_nil find_report("stuck").first
    end

    test "reports recent failures when count exceeds threshold" do
      QueueDepthAlert.new(
        recent_failure_threshold: 2,
        metrics: metrics(recent_failures: 3)
      ).call

      message, ctx = find_report("failures")

      refute_nil message
      assert_equal 3, ctx[:recent_failure_count]
    end

    test "does not report recent failures at or below threshold" do
      QueueDepthAlert.new(recent_failure_threshold: 2, metrics: metrics(recent_failures: 2)).call

      assert_nil find_report("failures").first
    end

    test "fires multiple independent alerts in one call" do
      QueueDepthAlert.new(
        ready_threshold: 2,
        recent_failure_threshold: 2,
        metrics: metrics(ready: 3, recent_failures: 3)
      ).call

      assert_equal 2, @reports.size
    end

    private

    def find_report(needle)
      @reports.find { |m, _| m.include?(needle) } || [ nil, nil ]
    end

    # rubocop:disable Metrics/ParameterLists
    def metrics(ready: 0, ready_breakdown: {}, stuck: 0, stuck_breakdown: {}, oldest_stuck_age_minutes: nil, recent_failures: 0)
      MetricsDouble.new(
        ready_count: ready,
        ready_breakdown: ready_breakdown,
        stuck_count: stuck,
        stuck_breakdown: stuck_breakdown,
        oldest_stuck_age_minutes: oldest_stuck_age_minutes,
        recent_failure_count: recent_failures
      )
    end
    # rubocop:enable Metrics/ParameterLists

    MetricsDouble = Struct.new(
      :ready_count, :ready_breakdown,
      :stuck_count, :stuck_breakdown, :oldest_stuck_age_minutes,
      :recent_failure_count,
      keyword_init: true
    )

    class TestErrorSubscriber
      def initialize(&block) = @block = block

      def report(error, **opts)
        @block.call(error, opts[:context])
      end
    end
  end
end
