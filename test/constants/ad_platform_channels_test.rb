# frozen_string_literal: true

require "test_helper"

class AdPlatformChannelsTest < ActiveSupport::TestCase
  # --- Google Campaign Type Map ---

  test "SEARCH maps to paid_search" do
    assert_equal Channels::PAID_SEARCH, AdPlatformChannels::GOOGLE_CAMPAIGN_TYPE_MAP["SEARCH"]
  end

  test "DISPLAY maps to display" do
    assert_equal Channels::DISPLAY, AdPlatformChannels::GOOGLE_CAMPAIGN_TYPE_MAP["DISPLAY"]
  end

  test "VIDEO maps to video" do
    assert_equal Channels::VIDEO, AdPlatformChannels::GOOGLE_CAMPAIGN_TYPE_MAP["VIDEO"]
  end

  test "SHOPPING maps to paid_search" do
    assert_equal Channels::PAID_SEARCH, AdPlatformChannels::GOOGLE_CAMPAIGN_TYPE_MAP["SHOPPING"]
  end

  test "DEMAND_GEN maps to paid_social" do
    assert_equal Channels::PAID_SOCIAL, AdPlatformChannels::GOOGLE_CAMPAIGN_TYPE_MAP["DEMAND_GEN"]
  end

  test "LOCAL maps to paid_search" do
    assert_equal Channels::PAID_SEARCH, AdPlatformChannels::GOOGLE_CAMPAIGN_TYPE_MAP["LOCAL"]
  end

  test "all campaign type values are valid channels" do
    AdPlatformChannels::GOOGLE_CAMPAIGN_TYPE_MAP.each_value do |channel|
      assert_includes Channels::ALL, channel
    end
  end

  # --- Google Network Type Map (PMax) ---

  test "SEARCH network maps to paid_search" do
    assert_equal Channels::PAID_SEARCH, AdPlatformChannels::GOOGLE_NETWORK_TYPE_MAP["SEARCH"]
  end

  test "CONTENT network maps to display" do
    assert_equal Channels::DISPLAY, AdPlatformChannels::GOOGLE_NETWORK_TYPE_MAP["CONTENT"]
  end

  test "YOUTUBE_WATCH network maps to video" do
    assert_equal Channels::VIDEO, AdPlatformChannels::GOOGLE_NETWORK_TYPE_MAP["YOUTUBE_WATCH"]
  end

  test "CROSS_NETWORK maps to paid_search as default" do
    assert_equal Channels::PAID_SEARCH, AdPlatformChannels::GOOGLE_NETWORK_TYPE_MAP["CROSS_NETWORK"]
  end

  test "all network type values are valid channels" do
    AdPlatformChannels::GOOGLE_NETWORK_TYPE_MAP.each_value do |channel|
      assert_includes Channels::ALL, channel
    end
  end

  # --- Maps are frozen ---

  test "campaign type map is frozen" do
    assert_predicate AdPlatformChannels::GOOGLE_CAMPAIGN_TYPE_MAP, :frozen?
  end

  test "network type map is frozen" do
    assert_predicate AdPlatformChannels::GOOGLE_NETWORK_TYPE_MAP, :frozen?
  end
end
