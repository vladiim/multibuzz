# frozen_string_literal: true

require "test_helper"

module Infrastructure
  class QueueCleanupJobTest < ActiveJob::TestCase
    test "delegates to QueueCleanup service" do
      assert_nothing_raised { QueueCleanupJob.perform_now }
    end
  end
end
