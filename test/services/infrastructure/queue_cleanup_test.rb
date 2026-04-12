# frozen_string_literal: true

require "test_helper"

module Infrastructure
  class QueueCleanupTest < ActiveSupport::TestCase
    test "stale threshold is 24 hours" do
      assert_equal 24.hours, QueueCleanup::STALE_THRESHOLD
    end

    test "alert threshold is 50" do
      assert_equal 50, QueueCleanup::ALERT_THRESHOLD
    end

    test "alert reports stuck count and breakdown in context" do
      reported_context = nil
      subscriber = TestErrorSubscriber.new { |_, ctx| reported_context = ctx }
      Rails.error.subscribe(subscriber)

      QueueCleanup.new.send(:alert_stuck_jobs, 75, { "SomeJob" => 50, "OtherJob" => 25 })

      Rails.error.unsubscribe(subscriber)

      assert_equal 75, reported_context[:stuck_count]
      assert_equal({ "SomeJob" => 50, "OtherJob" => 25 }, reported_context[:breakdown])
    end

    private

    class TestErrorSubscriber
      def initialize(&block) = @block = block

      def report(error, **opts)
        @block.call(error, opts[:context])
      end
    end
  end
end
