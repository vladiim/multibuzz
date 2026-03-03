# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Google::CampaignChannelMapperTest < ActiveSupport::TestCase
  # --- Standard campaign types ---

  test "maps SEARCH to paid_search" do
    assert_equal Channels::PAID_SEARCH, map(campaign_type: AdPlatformChannels::SEARCH)
  end

  test "maps DISPLAY to display" do
    assert_equal Channels::DISPLAY, map(campaign_type: AdPlatformChannels::DISPLAY)
  end

  test "maps VIDEO to video" do
    assert_equal Channels::VIDEO, map(campaign_type: AdPlatformChannels::VIDEO)
  end

  test "maps SHOPPING to paid_search" do
    assert_equal Channels::PAID_SEARCH, map(campaign_type: AdPlatformChannels::SHOPPING)
  end

  test "maps DEMAND_GEN to paid_social" do
    assert_equal Channels::PAID_SOCIAL, map(campaign_type: AdPlatformChannels::DEMAND_GEN)
  end

  test "maps LOCAL to paid_search" do
    assert_equal Channels::PAID_SEARCH, map(campaign_type: AdPlatformChannels::LOCAL)
  end

  test "maps unknown campaign type to paid_search" do
    assert_equal Channels::PAID_SEARCH, map(campaign_type: "UNKNOWN_FUTURE_TYPE")
  end

  # --- Performance Max ---

  test "maps PERFORMANCE_MAX with SEARCH network to paid_search" do
    assert_equal Channels::PAID_SEARCH, map(campaign_type: AdPlatformChannels::PERFORMANCE_MAX, network_type: AdPlatformChannels::NETWORK_SEARCH)
  end

  test "maps PERFORMANCE_MAX with CONTENT network to display" do
    assert_equal Channels::DISPLAY, map(campaign_type: AdPlatformChannels::PERFORMANCE_MAX, network_type: AdPlatformChannels::NETWORK_CONTENT)
  end

  test "maps PERFORMANCE_MAX with YOUTUBE_WATCH network to video" do
    assert_equal Channels::VIDEO, map(campaign_type: AdPlatformChannels::PERFORMANCE_MAX, network_type: AdPlatformChannels::NETWORK_YOUTUBE_WATCH)
  end

  test "maps PERFORMANCE_MAX with CROSS_NETWORK to paid_search" do
    assert_equal Channels::PAID_SEARCH, map(campaign_type: AdPlatformChannels::PERFORMANCE_MAX, network_type: AdPlatformChannels::NETWORK_CROSS_NETWORK)
  end

  test "maps PERFORMANCE_MAX with nil network to paid_search" do
    assert_equal Channels::PAID_SEARCH, map(campaign_type: AdPlatformChannels::PERFORMANCE_MAX, network_type: nil)
  end

  # --- User overrides ---

  test "applies channel override for specific campaign" do
    overrides = { "campaign_123" => Channels::DISPLAY }

    assert_equal Channels::DISPLAY, map(campaign_type: AdPlatformChannels::SEARCH, campaign_id: "123", overrides: overrides)
  end

  test "override takes precedence over default mapping" do
    overrides = { "campaign_456" => Channels::VIDEO }

    assert_equal Channels::VIDEO, map(campaign_type: AdPlatformChannels::DISPLAY, campaign_id: "456", overrides: overrides)
  end

  test "falls back to default when no override for campaign" do
    overrides = { "campaign_999" => Channels::VIDEO }

    assert_equal Channels::PAID_SEARCH, map(campaign_type: AdPlatformChannels::SEARCH, campaign_id: "123", overrides: overrides)
  end

  private

  def map(campaign_type:, network_type: nil, campaign_id: nil, overrides: {})
    AdPlatforms::Google::CampaignChannelMapper.call(
      campaign_type: campaign_type,
      network_type: network_type,
      campaign_id: campaign_id,
      channel_overrides: overrides
    )
  end
end
