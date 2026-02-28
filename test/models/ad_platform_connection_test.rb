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

  private

  def connection = @connection ||= ad_platform_connections(:google_ads)
end
