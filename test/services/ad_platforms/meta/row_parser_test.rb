# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Meta::RowParserTest < ActiveSupport::TestCase
  test "stamps account and connection ids from the connection" do
    parsed = parse(daily_row)

    assert_equal connection.account_id, parsed[:account_id]
    assert_equal connection.id, parsed[:ad_platform_connection_id]
  end

  test "parses spend string into micros" do
    parsed = parse(daily_row)

    assert_equal 12_340_000, parsed[:spend_micros]
  end

  test "parses impressions and clicks as integers" do
    parsed = parse(daily_row)

    assert_equal 1000, parsed[:impressions]
    assert_equal 50, parsed[:clicks]
  end

  test "parses spend_date from date_start" do
    parsed = parse(daily_row)

    assert_equal "2026-04-15", parsed[:spend_date]
  end

  test "defaults spend_hour to 0 for daily rows" do
    parsed = parse(daily_row)

    assert_equal 0, parsed[:spend_hour]
  end

  test "uses currency from the connection" do
    parsed = parse(daily_row)

    assert_equal "AUD", parsed[:currency]
  end

  test "defaults channel to paid_social" do
    parsed = parse(daily_row)

    assert_equal Channels::PAID_SOCIAL, parsed[:channel]
  end

  test "honours channel override via channel_overrides" do
    parsed = parse(daily_row, channel_overrides: { "campaign_120201234567" => "display" })

    assert_equal "display", parsed[:channel]
  end

  test "sums purchase action values into platform_conversions_micros" do
    parsed = parse(daily_row)

    assert_equal 5_000_000, parsed[:platform_conversions_micros]
  end

  test "sums purchase action_values into platform_conversion_value_micros" do
    parsed = parse(daily_row)

    assert_equal 299_950_000, parsed[:platform_conversion_value_micros]
  end

  test "tolerates missing actions arrays" do
    parsed = parse(daily_row.except("actions", "action_values"))

    assert_equal 0, parsed[:platform_conversions_micros]
    assert_equal 0, parsed[:platform_conversion_value_micros]
  end

  test "captures device when present" do
    parsed = parse(daily_row.merge("device_platform" => "mobile_app"))

    assert_equal "mobile_app", parsed[:device]
  end

  test "defaults device to ALL when missing" do
    parsed = parse(daily_row)

    assert_equal "ALL", parsed[:device]
  end

  test "captures platform_campaign_id, campaign_name, campaign_type" do
    parsed = parse(daily_row)

    assert_equal "120201234567", parsed[:platform_campaign_id]
    assert_equal "Brand Awareness", parsed[:campaign_name]
    assert_equal "OUTCOME_AWARENESS", parsed[:campaign_type]
  end

  test "network_type is nil for Meta" do
    parsed = parse(daily_row)

    assert_nil parsed[:network_type]
  end

  test "sums multiple purchase action types (omni_purchase, fb_pixel_purchase)" do
    row = daily_row.merge(
      "actions" => [
        { "action_type" => "purchase", "value" => "5" },
        { "action_type" => "omni_purchase", "value" => "3" },
        { "action_type" => "offsite_conversion.fb_pixel_purchase", "value" => "2" },
        { "action_type" => "add_to_cart", "value" => "10" }
      ]
    )

    assert_equal 10_000_000, parse(row)[:platform_conversions_micros]
  end

  private

  def parse(row, channel_overrides: nil)
    AdPlatforms::Meta::RowParser.call(row, connection: connection, channel_overrides: channel_overrides)
  end

  def connection = @connection ||= ad_platform_connections(:meta_ads)

  def daily_row
    {
      "campaign_id" => "120201234567",
      "campaign_name" => "Brand Awareness",
      "objective" => "OUTCOME_AWARENESS",
      "spend" => "12.34",
      "impressions" => "1000",
      "clicks" => "50",
      "actions" => [
        { "action_type" => "purchase", "value" => "5" },
        { "action_type" => "add_to_cart", "value" => "12" }
      ],
      "action_values" => [
        { "action_type" => "purchase", "value" => "299.95" }
      ],
      "date_start" => "2026-04-15"
    }
  end
end
