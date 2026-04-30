# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Google::RowParserTest < ActiveSupport::TestCase
  test "stamps connection metadata onto each row" do
    connection.update!(metadata: { "location" => "Sydney" })

    assert_equal({ "location" => "Sydney" }, parse(sample_row)[:metadata])
  end

  test "stamps empty metadata when connection has none" do
    assert_equal({}, parse(sample_row)[:metadata])
  end

  private

  def parse(row)
    AdPlatforms::Google::RowParser.call(row, connection: connection, channel_overrides: {})
  end

  def connection
    @connection ||= AdPlatformConnection.create!(
      account: accounts(:two),
      platform: :google_ads,
      platform_account_id: "1234567890",
      platform_account_name: "Google Parser Test",
      currency: "USD",
      access_token: "tok",
      refresh_token: "tok",
      token_expires_at: 30.days.from_now,
      status: :connected,
      settings: {}
    )
  end

  def sample_row
    {
      AdPlatforms::Google::FIELD_CAMPAIGN => {
        AdPlatforms::Google::FIELD_ID => "111",
        AdPlatforms::Google::FIELD_NAME => "Test Campaign",
        AdPlatforms::Google::FIELD_ADVERTISING_CHANNEL_TYPE => "SEARCH"
      },
      AdPlatforms::Google::FIELD_SEGMENTS => {
        AdPlatforms::Google::FIELD_DATE => "2026-04-15",
        AdPlatforms::Google::FIELD_HOUR => 0,
        AdPlatforms::Google::FIELD_DEVICE => "MOBILE",
        AdPlatforms::Google::FIELD_AD_NETWORK_TYPE => "SEARCH"
      },
      AdPlatforms::Google::FIELD_METRICS => {
        AdPlatforms::Google::FIELD_COST_MICROS => 1_000_000,
        AdPlatforms::Google::FIELD_IMPRESSIONS => 100,
        AdPlatforms::Google::FIELD_CLICKS => 5,
        AdPlatforms::Google::FIELD_CONVERSIONS => "1.0",
        AdPlatforms::Google::FIELD_CONVERSIONS_VALUE => "29.99"
      }
    }
  end
end
