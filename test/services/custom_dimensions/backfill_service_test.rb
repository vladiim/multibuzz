# frozen_string_literal: true

require "test_helper"

# Recomputes ad_spend_records.metadata from current dimensions, reading each
# row's stored campaign fields (no API call). See spec Phase 3.3.
class CustomDimensions::BackfillServiceTest < ActiveSupport::TestCase
  test "recomputes metadata from current by-campaign dimensions" do
    add_tier_dimension(contains: "brand", output: "Premium")

    CustomDimensions::BackfillService.new(account).call

    assert_equal "Premium", brand_search.reload.metadata["tier"]   # "Brand Search" matches
    assert_equal "Other", retargeting.reload.metadata["tier"]      # "Retargeting Display" → default
  end

  test "is idempotent" do
    add_tier_dimension(contains: "brand", output: "Premium")

    CustomDimensions::BackfillService.new(account).call
    first = brand_search.reload.metadata
    CustomDimensions::BackfillService.new(account).call

    assert_equal first, brand_search.reload.metadata
  end

  test "rebuilds from connection metadata, dropping keys with no live dimension" do
    connection.update!(metadata: { "brand" => "Acme" })
    brand_search.update_columns(metadata: { "brand" => "Acme", "stale" => "x" })

    CustomDimensions::BackfillService.new(account).call # no dimensions defined

    assert_equal({ "brand" => "Acme" }, brand_search.reload.metadata)
  end

  test "does not touch another account's records" do
    other = other_account_record(metadata: { "keep" => "me" })
    add_tier_dimension(contains: "brand", output: "Premium")

    CustomDimensions::BackfillService.new(account).call

    assert_equal({ "keep" => "me" }, other.reload.metadata)
  end

  private

  def add_tier_dimension(contains:, output:)
    dimension = account.custom_dimensions.create!(key: "tier", name: "Tier", mapping_mode: "campaign", default_value: "Other")
    dimension.dimension_rules.create!(
      account: account, position: 1, match_field: "campaign_name", operator: "contains", value: contains, output_value: output
    )
  end

  def other_account_record(metadata:)
    ad_platform_connections(:other_account_google).ad_spend_records.create!(
      account: accounts(:two), spend_date: Date.current, spend_hour: 0, channel: "paid_search",
      platform_campaign_id: "other_001", campaign_name: "Brand Other", currency: "USD",
      spend_micros: 0, impressions: 0, clicks: 0, device: "DESKTOP", metadata: metadata
    )
  end

  def account = @account ||= accounts(:one)
  def connection = @connection ||= ad_platform_connections(:google_ads)
  def brand_search = ad_spend_records(:paid_search_today)
  def retargeting = ad_spend_records(:display_today)
end
