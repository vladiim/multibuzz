# frozen_string_literal: true

require "test_helper"

class AdPlatforms::SpendSyncSchedulerJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "enqueues sync job for each active connection" do
    assert_enqueued_jobs active_connection_count, only: AdPlatforms::SpendSyncJob do
      AdPlatforms::SpendSyncSchedulerJob.perform_now
    end
  end

  test "skips disconnected connections" do
    count_before = active_connection_count
    connection.mark_disconnected!

    assert_enqueued_jobs count_before - 1, only: AdPlatforms::SpendSyncJob do
      AdPlatforms::SpendSyncSchedulerJob.perform_now
    end
  end

  private

  def connection = @connection ||= ad_platform_connections(:google_ads)

  def active_connection_count
    AdPlatformConnection.active_connections.count
  end
end
