# frozen_string_literal: true

require "test_helper"

class AdPlatforms::SpendSyncSchedulerJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  setup { Rails.cache.clear }

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

  test "sends api usage warning email for google_ads when approaching limit" do
    AdPlatforms::ApiUsageTracker.increment!(:google_ads, 12_500)

    assert_emails 1 do
      AdPlatforms::SpendSyncSchedulerJob.perform_now
    end
  end

  test "sends api usage warning email for meta_ads when approaching limit" do
    AdPlatforms::ApiUsageTracker.increment!(:meta_ads, 170_000)

    assert_emails 1 do
      AdPlatforms::SpendSyncSchedulerJob.perform_now
    end
  end

  test "sends one warning per platform when both are approaching" do
    AdPlatforms::ApiUsageTracker.increment!(:google_ads, 12_500)
    AdPlatforms::ApiUsageTracker.increment!(:meta_ads, 170_000)

    assert_emails 2 do
      AdPlatforms::SpendSyncSchedulerJob.perform_now
    end
  end

  test "does not send email when below threshold" do
    assert_no_emails do
      AdPlatforms::SpendSyncSchedulerJob.perform_now
    end
  end

  test "sends at most one warning email per platform per day" do
    AdPlatforms::ApiUsageTracker.increment!(:google_ads, 12_500)

    assert_emails 1 do
      AdPlatforms::SpendSyncSchedulerJob.perform_now
      AdPlatforms::SpendSyncSchedulerJob.perform_now
    end
  end

  test "warning cache is per-platform — meta warning does not suppress google warning" do
    AdPlatforms::ApiUsageTracker.increment!(:meta_ads, 170_000)
    AdPlatforms::SpendSyncSchedulerJob.perform_now

    AdPlatforms::ApiUsageTracker.increment!(:google_ads, 12_500)

    assert_emails 1 do
      AdPlatforms::SpendSyncSchedulerJob.perform_now
    end
  end

  private

  def connection = @connection ||= ad_platform_connections(:google_ads)

  def active_connection_count
    AdPlatformConnection.active_connections.count
  end
end
