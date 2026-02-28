# frozen_string_literal: true

module AdPlatformChannels
  # --- Google Ads: campaign.advertising_channel_type → mbuzz channel ---

  GOOGLE_CAMPAIGN_TYPE_MAP = {
    "SEARCH" => Channels::PAID_SEARCH,
    "DISPLAY" => Channels::DISPLAY,
    "VIDEO" => Channels::VIDEO,
    "SHOPPING" => Channels::PAID_SEARCH,
    "DEMAND_GEN" => Channels::PAID_SOCIAL,
    "LOCAL" => Channels::PAID_SEARCH
  }.freeze

  # --- Google Ads: Performance Max segments.ad_network_type → mbuzz channel ---

  GOOGLE_NETWORK_TYPE_MAP = {
    "SEARCH" => Channels::PAID_SEARCH,
    "CONTENT" => Channels::DISPLAY,
    "YOUTUBE_SEARCH" => Channels::VIDEO,
    "YOUTUBE_WATCH" => Channels::VIDEO,
    "CROSS_NETWORK" => Channels::PAID_SEARCH
  }.freeze
end
