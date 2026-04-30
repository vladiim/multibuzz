# frozen_string_literal: true

require "test_helper"

class AdPlatforms::MetadataBackfillServiceTest < ActiveSupport::TestCase
  test "stamps the connection's metadata onto every spend record for that connection" do
    connection.update!(metadata: { "location" => "Eumundi-Noosa" })

    service.call

    spend_records.each do |record|
      assert_equal({ "location" => "Eumundi-Noosa" }, record.reload.metadata)
    end
  end

  test "returns success with the count of records updated" do
    connection.update!(metadata: { "location" => "Sydney" })

    result = service.call

    assert result[:success]
    assert_equal spend_records.size, result[:records_updated]
  end

  test "leaves spend records belonging to other connections untouched" do
    other_connection.ad_spend_records.update_all(metadata: { "location" => "Melbourne" })
    other_connection.update!(metadata: { "location" => "Sydney" })
    connection.update!(metadata: { "location" => "Eumundi-Noosa" })

    service.call

    other_connection.ad_spend_records.each do |record|
      assert_equal({ "location" => "Melbourne" }, record.reload.metadata)
    end
  end

  test "leaves spend records in other accounts untouched" do
    connection.update!(metadata: { "location" => "Eumundi-Noosa" })
    cross_account_record = AdSpendRecord.create!(
      account: accounts(:two),
      ad_platform_connection: ad_platform_connections(:other_account_google),
      spend_date: Date.current,
      spend_hour: 12,
      channel: "paid_search",
      platform_campaign_id: "x",
      campaign_name: "x",
      currency: "AUD",
      spend_micros: 0,
      metadata: { "location" => "Brisbane" }
    )

    service.call

    assert_equal({ "location" => "Brisbane" }, cross_account_record.reload.metadata)
  end

  test "fully replaces existing metadata rather than merging" do
    spend_records.first.update!(metadata: { "location" => "old", "brand" => "premium" })
    connection.update!(metadata: { "location" => "new" })

    service.call

    assert_equal({ "location" => "new" }, spend_records.first.reload.metadata)
  end

  test "is a no-op when the connection has no spend records" do
    empty_connection = ad_platform_connections(:google_ads_error)
    empty_connection.ad_spend_records.delete_all
    empty_connection.update!(metadata: { "location" => "Cairns" })

    result = AdPlatforms::MetadataBackfillService.new(empty_connection).call

    assert result[:success]
    assert_equal 0, result[:records_updated]
  end

  private

  def service = @service ||= AdPlatforms::MetadataBackfillService.new(connection)
  def connection = @connection ||= ad_platform_connections(:google_ads)
  def other_connection = @other_connection ||= ad_platform_connections(:other_account_google)
  def spend_records = @spend_records ||= connection.ad_spend_records.to_a
end
