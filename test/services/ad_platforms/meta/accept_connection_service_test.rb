# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Meta::AcceptConnectionServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creates a connected meta_ads AdPlatformConnection when account has room" do
    account.update!(plan: growth_plan)

    assert_difference "AdPlatformConnection.count", 1 do
      service.call
    end

    assert_predicate created_connection, :connected?
  end

  test "stamps platform=meta_ads on the new connection" do
    account.update!(plan: growth_plan)
    service.call

    assert_equal "meta_ads", created_connection.platform
  end

  test "stamps account name and currency from selected ad account" do
    account.update!(plan: growth_plan)
    service.call

    assert_equal "Sydney Petlands (test)", created_connection.platform_account_name
    assert_equal "AUD", created_connection.currency
  end

  test "persists encrypted access token" do
    account.update!(plan: growth_plan)
    service.call

    assert_equal "long_lived_test_token", created_connection.access_token
  end

  test "persists token_expires_at" do
    account.update!(plan: growth_plan)
    service.call

    assert_in_delta tokens[:expires_at].to_i, created_connection.token_expires_at.to_i, 2
  end

  test "captures timezone in connection settings" do
    account.update!(plan: growth_plan)
    service.call

    assert_equal "Australia/Sydney", created_connection.settings["timezone_name"]
  end

  test "enqueues SpendSyncJob for backfill" do
    account.update!(plan: growth_plan)

    assert_enqueued_with(job: AdPlatforms::SpendSyncJob) do
      service.call
    end
  end

  test "returns success outcome with notice and clear_session" do
    account.update!(plan: growth_plan)
    outcome = service.call

    assert_match(/Meta/i, outcome[:notice])
    assert outcome[:clear_session]
  end

  test "returns at-limit outcome when account has no remaining slots" do
    account.update!(plan: free_plan)
    outcome = service.call

    assert_predicate outcome[:alert], :present?
    assert_nil outcome[:notice]
  end

  test "does not create connection when at limit" do
    account.update!(plan: free_plan)

    assert_no_difference "AdPlatformConnection.count" do
      service.call
    end
  end

  test "returns duplicate outcome when ad_account_id already connected" do
    account.update!(plan: growth_plan)
    AdPlatformConnection.create!(
      account: account,
      platform: :meta_ads,
      platform_account_id: "act_TEST_001",
      platform_account_name: "existing",
      currency: "AUD",
      access_token: "x",
      refresh_token: "x",
      token_expires_at: 1.hour.from_now,
      status: :connected,
      settings: {}
    )

    outcome = service.call

    assert_match(/already connected/i, outcome[:alert])
  end

  test "scopes duplicate check to the given account" do
    account.update!(plan: growth_plan)
    other_account.update!(plan: growth_plan)
    AdPlatformConnection.create!(
      account: other_account,
      platform: :meta_ads,
      platform_account_id: "act_TEST_001",
      platform_account_name: "other-acc-meta",
      currency: "AUD",
      access_token: "x",
      refresh_token: "x",
      token_expires_at: 1.hour.from_now,
      status: :connected,
      settings: {}
    )

    assert_difference "AdPlatformConnection.count", 1 do
      service.call
    end
  end

  test "stamps normalized metadata onto the connection" do
    account.update!(plan: growth_plan)

    AdPlatforms::Meta::AcceptConnectionService.new(
      account: account, params: params, tokens: tokens,
      metadata: { "Location" => "Eumundi-Noosa" }
    ).call

    assert_equal({ "location" => "Eumundi-Noosa" }, created_connection.metadata)
  end

  test "leaves metadata empty when no metadata passed" do
    account.update!(plan: growth_plan)
    service.call

    assert_equal({}, created_connection.metadata)
  end

  private

  def service
    @service ||= AdPlatforms::Meta::AcceptConnectionService.new(
      account: account,
      params: params,
      tokens: tokens
    )
  end

  def created_connection
    account.ad_platform_connections.find_by(platform_account_id: "act_TEST_001")
  end

  def account = @account ||= accounts(:one)
  def other_account = @other_account ||= accounts(:two)
  def free_plan = @free_plan ||= plans(:free)
  def growth_plan = @growth_plan ||= plans(:growth)

  def params
    {
      ad_account_id: "act_TEST_001",
      ad_account_name: "Sydney Petlands (test)",
      currency: "AUD",
      timezone_name: "Australia/Sydney"
    }
  end

  def tokens
    { access_token: "long_lived_test_token", expires_at: 60.days.from_now }
  end
end
