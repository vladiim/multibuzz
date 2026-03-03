# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AdPlatforms::Google::ConnectionSyncServiceTest < ActiveSupport::TestCase
  test "creates completed sync run on success" do
    stub_sync(success: true, records_synced: 5) do
      assert_difference "AdSpendSyncRun.count", 1 do
        service.call
      end
    end

    run = connection.ad_spend_sync_runs.last

    assert_predicate run, :completed?
    assert_equal 5, run.records_synced
  end

  test "marks connection as connected after successful sync" do
    stub_sync(success: true, records_synced: 1) do
      service.call
    end

    assert_predicate connection.reload, :connected?
  end

  test "creates failed sync run on service error" do
    stub_sync(success: false, error: "API error") do
      assert_difference "AdSpendSyncRun.count", 1 do
        service.call
      end
    end

    run = connection.ad_spend_sync_runs.last

    assert_predicate run, :failed?
    assert_equal "API error", run.error_message
  end

  test "marks connection as error on service failure" do
    stub_sync(success: false, error: "API error") do
      service.call
    end

    assert_predicate connection.reload, :error?
    assert_equal "API error", connection.last_sync_error
  end

  test "refreshes token before syncing if expired" do
    connection.update!(token_expires_at: 1.hour.ago)

    stub_token_refresh(success: true) do
      stub_sync(success: true, records_synced: 1) do
        service.call
      end
    end

    assert_operator connection.reload.token_expires_at, :>, Time.current
  end

  test "creates failed sync run when token refresh fails" do
    connection.update!(token_expires_at: 1.hour.ago, refresh_token: nil)

    assert_difference "AdSpendSyncRun.count", 1 do
      service.call
    end

    run = connection.ad_spend_sync_runs.last

    assert_predicate run, :failed?
  end

  test "marks connection as error when token refresh fails" do
    connection.update!(token_expires_at: 1.hour.ago, refresh_token: nil)

    service.call

    assert_predicate connection.reload, :error?
  end

  test "uses provided date range when given" do
    synced_range = nil
    custom_range = 90.days.ago.to_date..Date.current

    AdPlatforms::Google::SpendSyncService.stub(:new, ->(_conn, date_range:, **_opts) {
      synced_range = date_range
      OpenStruct.new(call: { success: true, records_synced: 0 })
    }) do
      AdPlatforms::Google::ConnectionSyncService.new(connection, date_range: custom_range).call
    end

    assert_equal custom_range, synced_range
  end

  test "syncs last 3 days for incremental sync" do
    synced_range = nil

    AdPlatforms::Google::SpendSyncService.stub(:new, ->(_conn, date_range:, **_opts) {
      synced_range = date_range
      OpenStruct.new(call: { success: true, records_synced: 0 })
    }) do
      service.call
    end

    assert_equal 3.days.ago.to_date, synced_range.first
    assert_equal Date.current, synced_range.last
  end

  private

  def service
    @service ||= AdPlatforms::Google::ConnectionSyncService.new(connection)
  end

  def connection = @connection ||= ad_platform_connections(:google_ads)

  def stub_sync(success:, records_synced: 0, error: nil)
    result = success ? { success: true, records_synced: records_synced } : { success: false, errors: [ error ] }

    AdPlatforms::Google::SpendSyncService.stub(:new, ->(_conn, **_opts) {
      OpenStruct.new(call: result)
    }) do
      yield
    end
  end

  def stub_token_refresh(success:)
    result = if success
      { success: true, access_token: "refreshed_token", expires_at: 1.hour.from_now }
    else
      { success: false, errors: [ "No refresh token available" ] }
    end

    AdPlatforms::Google::TokenRefresher.stub(:new, ->(_conn) {
      OpenStruct.new(call: result)
    }) do
      yield
    end
  end
end
