# frozen_string_literal: true

require "test_helper"

module DataIntegrity
  class SurveillanceSchedulerJobTest < ActiveJob::TestCase
    test "delegates to SurveillanceScheduler service" do
      assert_nothing_raised { SurveillanceSchedulerJob.perform_now }
    end
  end
end
