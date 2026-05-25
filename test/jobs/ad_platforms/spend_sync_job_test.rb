# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AdPlatforms::SpendSyncJobTest < ActiveSupport::TestCase
  test "dispatches Google connection to Google::ConnectionSyncService" do
    called_with = nil

    AdPlatforms::Google::ConnectionSyncService.stub(:new, ->(conn, **_opts) {
      called_with = conn
      OpenStruct.new(call: nil)
    }) do
      AdPlatforms::SpendSyncJob.perform_now(google_connection.id)
    end

    assert_equal google_connection, called_with
  end

  test "dispatches Meta connection to Meta::ConnectionSyncService" do
    called_with = nil

    AdPlatforms::Meta::ConnectionSyncService.stub(:new, ->(conn, **_opts) {
      called_with = conn
      OpenStruct.new(call: nil)
    }) do
      AdPlatforms::SpendSyncJob.perform_now(meta_connection.id)
    end

    assert_equal meta_connection, called_with
  end

  private

  def google_connection = @google_connection ||= ad_platform_connections(:google_ads)

  def meta_connection
    @meta_connection ||= AdPlatformConnection.create!(
      account: accounts(:one),
      platform: :meta_ads,
      platform_account_id: "act_meta_test",
      platform_account_name: "Meta Test Account",
      currency: "USD",
      access_token: "test_meta_token",
      token_expires_at: 1.hour.from_now,
      status: :connected
    )
  end
end
