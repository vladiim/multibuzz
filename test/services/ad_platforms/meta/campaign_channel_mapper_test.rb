# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Meta::CampaignChannelMapperTest < ActiveSupport::TestCase
  test "defaults Meta campaigns to paid_social" do
    assert_equal Channels::PAID_SOCIAL,
      AdPlatforms::Meta::CampaignChannelMapper.call(campaign_id: "123")
  end

  test "honours per-campaign override from connection settings" do
    overrides = { "campaign_123" => "display" }

    assert_equal "display",
      AdPlatforms::Meta::CampaignChannelMapper.call(campaign_id: "123", channel_overrides: overrides)
  end

  test "falls back to default when override key does not match" do
    overrides = { "campaign_999" => "display" }

    assert_equal Channels::PAID_SOCIAL,
      AdPlatforms::Meta::CampaignChannelMapper.call(campaign_id: "123", channel_overrides: overrides)
  end

  test "treats nil overrides as no overrides" do
    assert_equal Channels::PAID_SOCIAL,
      AdPlatforms::Meta::CampaignChannelMapper.call(campaign_id: "123", channel_overrides: nil)
  end
end
