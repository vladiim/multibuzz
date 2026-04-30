# frozen_string_literal: true

require "test_helper"

class AdPlatformConnectionTest < ActiveSupport::TestCase
  # --- Relationships ---

  test "belongs to account" do
    assert_equal accounts(:one), connection.account
  end

  test "has many ad_spend_records" do
    assert_respond_to connection, :ad_spend_records
    assert_predicate connection.ad_spend_records.count, :positive?
  end

  test "has many ad_spend_sync_runs" do
    assert_respond_to connection, :ad_spend_sync_runs
  end

  # --- Validations ---

  test "requires platform" do
    connection.platform = nil

    assert_not connection.valid?
  end

  test "requires platform_account_id" do
    connection.platform_account_id = nil

    assert_not connection.valid?
    assert_includes connection.errors[:platform_account_id], "can't be blank"
  end

  test "requires currency" do
    connection.currency = nil

    assert_not connection.valid?
    assert_includes connection.errors[:currency], "can't be blank"
  end

  test "enforces unique platform_account_id per account and platform" do
    duplicate = connection.dup

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:platform_account_id], "has already been taken"
  end

  # --- Enums ---

  test "platform enum includes google_ads" do
    assert_equal 0, AdPlatformConnection.platforms[:google_ads]
  end

  test "platform enum includes meta_ads" do
    assert_equal 1, AdPlatformConnection.platforms[:meta_ads]
  end

  test "platform enum includes linkedin_ads and tiktok_ads" do
    assert_equal 2, AdPlatformConnection.platforms[:linkedin_ads]
    assert_equal 3, AdPlatformConnection.platforms[:tiktok_ads]
  end

  test "status enum includes connected and syncing" do
    assert_equal 0, AdPlatformConnection.statuses[:connected]
    assert_equal 1, AdPlatformConnection.statuses[:syncing]
  end

  test "status enum includes error and disconnected" do
    assert_equal 2, AdPlatformConnection.statuses[:error]
    assert_equal 3, AdPlatformConnection.statuses[:disconnected]
  end

  test "status enum includes needs_reauth" do
    assert_equal 4, AdPlatformConnection.statuses[:needs_reauth]
  end

  # --- Encryption ---

  test "encrypts access_token" do
    assert_equal "test_access_token", connection.access_token
  end

  test "encrypts refresh_token" do
    assert_equal "test_refresh_token", connection.refresh_token
  end

  # --- Status Management ---

  test "token_expired? returns true when token is past expiry" do
    error_connection = ad_platform_connections(:google_ads_error)

    assert_predicate error_connection, :token_expired?
  end

  test "token_expired? returns false when token is still valid" do
    assert_not connection.token_expired?
  end

  test "mark_syncing! updates status" do
    connection.mark_syncing!

    assert_predicate connection, :syncing?
  end

  test "mark_connected! updates status and clears error" do
    error_connection = ad_platform_connections(:google_ads_error)
    error_connection.mark_connected!

    assert_predicate error_connection, :connected?
    assert_nil error_connection.last_sync_error
    assert_not_nil error_connection.last_synced_at
  end

  test "mark_error! updates status and sets error message" do
    connection.mark_error!("Something broke")

    assert_predicate connection, :error?
    assert_equal "Something broke", connection.last_sync_error
  end

  test "mark_needs_reauth! sets status" do
    connection.mark_needs_reauth!

    assert_predicate connection, :needs_reauth?
  end

  test "mark_needs_reauth! preserves tokens" do
    connection.mark_needs_reauth!

    assert_not_nil connection.access_token
    assert_not_nil connection.refresh_token
  end

  test "active_connections excludes needs_reauth" do
    connection.mark_needs_reauth!

    assert_not_includes AdPlatformConnection.active_connections, connection
  end

  test "mark_disconnected! sets status" do
    connection.mark_disconnected!

    assert_predicate connection, :disconnected?
  end

  test "mark_disconnected! clears tokens" do
    connection.mark_disconnected!

    assert_nil connection.access_token
    assert_nil connection.refresh_token
    assert_nil connection.token_expires_at
  end

  # --- Ad Spend ---

  test "spend_date_range returns min and max spend dates" do
    range = connection.spend_date_range

    assert_instance_of Date, range.first
    assert_instance_of Date, range.last
  end

  test "spend_date_range returns nil pair when no records" do
    other = ad_platform_connections(:google_ads_error)
    other.ad_spend_records.delete_all

    assert_nil other.spend_date_range.first
  end

  test "spend_records_count returns count of ad spend records" do
    assert_predicate connection.spend_records_count, :positive?
  end

  test "recent_sync_runs returns ordered sync runs" do
    connection.ad_spend_sync_runs.create!(sync_date: Date.current, status: :completed, records_synced: 10, started_at: 1.minute.ago, completed_at: Time.current)

    runs = connection.recent_sync_runs

    assert_equal runs.first.created_at, runs.map(&:created_at).max
  end

  test "verification_data returns yesterday's spend summary" do
    connection.ad_spend_records.where(spend_date: Date.yesterday).delete_all

    connection.ad_spend_records.create!(
      account: connection.account, spend_date: Date.yesterday, spend_hour: 10,
      channel: "paid_search", platform_campaign_id: "c1", campaign_name: "Campaign A",
      device: "DESKTOP", spend_micros: 5_000_000, currency: "USD",
      impressions: 100, clicks: 10, platform_conversions_micros: 0, platform_conversion_value_micros: 0, is_test: false
    )
    connection.ad_spend_records.create!(
      account: connection.account, spend_date: Date.yesterday, spend_hour: 11,
      channel: "paid_search", platform_campaign_id: "c2", campaign_name: "Campaign B",
      device: "MOBILE", spend_micros: 3_000_000, currency: "USD",
      impressions: 50, clicks: 5, platform_conversions_micros: 0, platform_conversion_value_micros: 0, is_test: false
    )

    data = connection.verification_data

    assert_equal 8_000_000, data[:spend_micros]
    assert_equal 2, data[:campaign_count]
  end

  test "verification_data returns nil when no yesterday data" do
    connection.ad_spend_records.where(spend_date: Date.yesterday).delete_all

    assert_nil connection.verification_data
  end

  test "verification_dismissed? reads from settings" do
    assert_not connection.verification_dismissed?

    connection.update!(settings: { AdPlatformConnection::SETTING_VERIFICATION_DISMISSED => true })

    assert_predicate connection, :verification_dismissed?
  end

  # --- Prefix ID ---

  test "has adcon prefix id" do
    assert connection.prefix_id.start_with?("adcon_")
  end

  # --- Multi-tenancy ---

  test "account one cannot access account two connections" do
    account_one_connections = accounts(:one).ad_platform_connections
    other = ad_platform_connections(:other_account_google)

    assert_not_includes account_one_connections, other
  end

  # --- Metadata ---

  test "metadata defaults to empty hash" do
    new_conn = accounts(:one).ad_platform_connections.build(
      platform: :meta_ads, platform_account_id: "act_x", currency: "USD"
    )

    assert_equal({}, new_conn.metadata)
  end

  test "metadata accepts string keys and values" do
    connection.update!(metadata: { "location" => "Sydney", "brand" => "Premium" })

    assert_equal "Sydney", connection.reload.metadata["location"]
  end

  test "metadata is invalid when not a hash" do
    connection.metadata = "not a hash"

    assert_not connection.valid?
    assert_includes connection.errors[:metadata], "must be a hash"
  end

  test "metadata is invalid when over 5KB" do
    connection.metadata = { "blob" => "x" * 6_000 }

    assert_not connection.valid?
    assert_includes connection.errors[:metadata], "must be less than 5KB"
  end

  private

  def connection = @connection ||= ad_platform_connections(:google_ads)
end
