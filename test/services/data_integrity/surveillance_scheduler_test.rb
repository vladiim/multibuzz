# frozen_string_literal: true

require "test_helper"

module DataIntegrity
  class SurveillanceSchedulerTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "enqueues surveillance job for active accounts" do
      assert_enqueued_with(job: SurveillanceJob) do
        service.call
      end
    end

    private

    def service
      @service ||= SurveillanceScheduler.new
    end
  end
end
