# frozen_string_literal: true

require "test_helper"

module Infrastructure
  class HealthCheckJobTest < ActiveSupport::TestCase
    test "performs without error" do
      assert_nothing_raised do
        Infrastructure::HealthCheckJob.perform_now
      end
    end
  end
end
