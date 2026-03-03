# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AdPlatforms::SpendSyncJobTest < ActiveSupport::TestCase
  test "delegates to ConnectionSyncService" do
    called = false

    AdPlatforms::Google::ConnectionSyncService.stub(:new, ->(conn, **_opts) {
      called = true

      assert_equal connection, conn
      OpenStruct.new(call: nil)
    }) do
      AdPlatforms::SpendSyncJob.perform_now(connection.id)
    end

    assert called
  end

  private

  def connection = @connection ||= ad_platform_connections(:google_ads)
end
