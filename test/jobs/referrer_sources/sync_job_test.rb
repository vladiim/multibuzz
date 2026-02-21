# frozen_string_literal: true

require "test_helper"

class ReferrerSources::SyncJobTest < ActiveSupport::TestCase
  test "enqueues on default queue" do
    assert_equal "default", ReferrerSources::SyncJob.new.queue_name
  end
end
