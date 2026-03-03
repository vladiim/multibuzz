# frozen_string_literal: true

module AdPlatformChannels
  # --- Google Ads campaign types (campaign.advertising_channel_type) ---

  SEARCH = "SEARCH"
  DISPLAY = "DISPLAY"
  VIDEO = "VIDEO"
  SHOPPING = "SHOPPING"
  DEMAND_GEN = "DEMAND_GEN"
  LOCAL = "LOCAL"
  PERFORMANCE_MAX = "PERFORMANCE_MAX"

  # --- Google Ads network types (segments.ad_network_type) ---

  NETWORK_SEARCH = "SEARCH"
  NETWORK_CONTENT = "CONTENT"
  NETWORK_YOUTUBE_SEARCH = "YOUTUBE_SEARCH"
  NETWORK_YOUTUBE_WATCH = "YOUTUBE_WATCH"
  NETWORK_CROSS_NETWORK = "CROSS_NETWORK"

  # --- Campaign type → mbuzz channel ---

  GOOGLE_CAMPAIGN_TYPE_MAP = {
    SEARCH => Channels::PAID_SEARCH,
    DISPLAY => Channels::DISPLAY,
    VIDEO => Channels::VIDEO,
    SHOPPING => Channels::PAID_SEARCH,
    DEMAND_GEN => Channels::PAID_SOCIAL,
    LOCAL => Channels::PAID_SEARCH
  }.freeze

  # --- Performance Max network type → mbuzz channel ---

  GOOGLE_NETWORK_TYPE_MAP = {
    NETWORK_SEARCH => Channels::PAID_SEARCH,
    NETWORK_CONTENT => Channels::DISPLAY,
    NETWORK_YOUTUBE_SEARCH => Channels::VIDEO,
    NETWORK_YOUTUBE_WATCH => Channels::VIDEO,
    NETWORK_CROSS_NETWORK => Channels::PAID_SEARCH
  }.freeze
end
