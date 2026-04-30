# frozen_string_literal: true

require "test_helper"

class AdPlatforms::MetadataBackfillJobTest < ActiveSupport::TestCase
  test "backfills metadata onto the connection's spend records" do
    connection.update!(metadata: { "location" => "Eumundi-Noosa" })

    AdPlatforms::MetadataBackfillJob.perform_now(connection.id)

    assert_predicate connection.ad_spend_records, :any?
    connection.ad_spend_records.each do |record|
      assert_equal({ "location" => "Eumundi-Noosa" }, record.reload.metadata)
    end
  end

  private

  def connection = @connection ||= ad_platform_connections(:google_ads)
end
