# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Google::AcceptConnectionServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # --- success path ---

  test "creates a connected AdPlatformConnection when account has room" do
    account.update!(plan: growth_plan)

    assert_difference "AdPlatformConnection.count", 1 do
      service.call
    end

    conn = account.ad_platform_connections.find_by(platform_account_id: "new-555")

    assert_predicate conn, :connected?
    assert_equal "New Ads", conn.platform_account_name
  end

  test "persists encrypted tokens from session" do
    account.update!(plan: growth_plan)

    service.call

    conn = account.ad_platform_connections.find_by(platform_account_id: "new-555")

    assert_equal "access_123", conn.access_token
    assert_equal "refresh_456", conn.refresh_token
  end

  test "persists login_customer_id setting when present" do
    account.update!(plan: growth_plan)

    AdPlatforms::Google::AcceptConnectionService.new(
      account: account,
      params: params.merge(login_customer_id: "mgr-001"),
      tokens: tokens
    ).call

    conn = account.ad_platform_connections.find_by(platform_account_id: "new-555")

    assert_equal "mgr-001", conn.settings["login_customer_id"]
  end

  test "enqueues SpendSyncJob for backfill" do
    account.update!(plan: growth_plan)

    assert_enqueued_with(job: AdPlatforms::SpendSyncJob) do
      service.call
    end
  end

  test "returns success outcome with notice and keeps session alive for multi-connect" do
    account.update!(plan: growth_plan)

    outcome = service.call

    assert_match(/Google Ads account connected/, outcome[:notice])
    assert_not outcome[:clear_session]
    assert_nil outcome[:alert]
  end

  # --- at-limit ---

  test "returns at-limit outcome when account has no remaining slots" do
    account.update!(plan: starter_plan)
    # fixture already has 2 connections; starter limit is 2

    outcome = service.call

    assert_match(/2 of 2/i, outcome[:alert])
    assert_match(/upgrade/i, outcome[:alert])
    assert outcome[:clear_session]
  end

  test "does not create connection when at limit" do
    account.update!(plan: starter_plan)

    assert_no_difference "AdPlatformConnection.count" do
      service.call
    end
  end

  test "does not enqueue backfill when at limit" do
    account.update!(plan: starter_plan)

    assert_no_enqueued_jobs(only: AdPlatforms::SpendSyncJob) do
      service.call
    end
  end

  test "returns at-limit outcome for free plan" do
    account.update!(plan: free_plan)

    outcome = service.call

    assert_predicate outcome[:alert], :present?
    assert_nil outcome[:notice]
  end

  # --- duplicate ---

  test "returns duplicate outcome when platform_account_id already connected" do
    account.update!(plan: growth_plan)

    outcome = AdPlatforms::Google::AcceptConnectionService.new(
      account: account,
      params: params.merge(customer_id: existing_connection.platform_account_id),
      tokens: tokens
    ).call

    assert_match(/already connected/i, outcome[:alert])
    assert_not outcome[:clear_session]
  end

  test "does not create duplicate connection" do
    account.update!(plan: growth_plan)

    assert_no_difference "AdPlatformConnection.count" do
      AdPlatforms::Google::AcceptConnectionService.new(
        account: account,
        params: params.merge(customer_id: existing_connection.platform_account_id),
        tokens: tokens
      ).call
    end
  end

  # --- lifecycle tracking ---

  test "fires feature_ad_platform_connected with platform and connection counts" do
    account.update!(plan: growth_plan)

    service.call

    assert(tracked_event, "expected feature_ad_platform_connected to be recorded")
    assert_equal "google_ads", tracked_event[:properties][:platform]
    assert_equal account.ad_platform_connection_limit, tracked_event[:properties][:connection_limit]
  end

  test "does not fire feature_ad_platform_connected on at-limit failure" do
    account.update!(plan: starter_plan)

    service.call

    assert_nil tracked_event
  end

  test "does not fire feature_ad_platform_connected on duplicate failure" do
    account.update!(plan: growth_plan)

    AdPlatforms::Google::AcceptConnectionService.new(
      account: account,
      params: params.merge(customer_id: existing_connection.platform_account_id),
      tokens: tokens
    ).call

    assert_nil tracked_event
  end

  # --- isolation ---

  test "scopes duplicate check to the given account" do
    account.update!(plan: growth_plan)
    # other_account has its own connection; reusing its customer_id on this account is not a duplicate

    assert_difference "AdPlatformConnection.count", 1 do
      AdPlatforms::Google::AcceptConnectionService.new(
        account: account,
        params: params.merge(customer_id: other_account_connection.platform_account_id),
        tokens: tokens
      ).call
    end
  end

  private

  def service
    @service ||= AdPlatforms::Google::AcceptConnectionService.new(
      account: account,
      params: params,
      tokens: tokens
    )
  end

  def account = @account ||= accounts(:one)
  def other_account = @other_account ||= accounts(:two)
  def free_plan = @free_plan ||= plans(:free)
  def starter_plan = @starter_plan ||= plans(:starter)
  def growth_plan = @growth_plan ||= plans(:growth)
  def existing_connection = @existing_connection ||= ad_platform_connections(:google_ads)
  def tracked_event = Lifecycle::Tracker.recorded_events.find { |e| e[:name] == "feature_ad_platform_connected" }
  def other_account_connection = @other_account_connection ||= ad_platform_connections(:other_account_google)

  def params
    ActionController::Parameters.new(
      customer_id: "new-555",
      customer_name: "New Ads",
      currency: "USD"
    ).permit!
  end

  def tokens
    {
      "access_token" => "access_123",
      "refresh_token" => "refresh_456",
      "expires_at" => 1.hour.from_now.iso8601
    }
  end
end
