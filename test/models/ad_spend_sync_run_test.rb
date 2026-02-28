# frozen_string_literal: true

require "test_helper"

class AdSpendSyncRunTest < ActiveSupport::TestCase
  # --- Relationships ---

  test "belongs to ad_platform_connection" do
    assert_equal ad_platform_connections(:google_ads), sync_run.ad_platform_connection
  end

  # --- Validations ---

  test "requires sync_date" do
    sync_run.sync_date = nil

    assert_not sync_run.valid?
  end

  # --- Enums ---

  test "status enum includes pending and running" do
    assert_equal 0, AdSpendSyncRun.statuses[:pending]
    assert_equal 1, AdSpendSyncRun.statuses[:running]
  end

  test "status enum includes completed and failed" do
    assert_equal 2, AdSpendSyncRun.statuses[:completed]
    assert_equal 3, AdSpendSyncRun.statuses[:failed]
  end

  test "completed run has records_synced" do
    assert_equal 42, sync_run.records_synced
  end

  test "failed run has error_message" do
    failed = ad_spend_sync_runs(:failed_run)

    assert_equal "API rate limit exceeded", failed.error_message
    assert_predicate failed, :failed?
  end

  private

  def sync_run = @sync_run ||= ad_spend_sync_runs(:completed_run)
end
