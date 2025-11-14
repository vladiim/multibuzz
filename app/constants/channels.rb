module Channels
  # Channel taxonomy - standard marketing channels
  PAID_SEARCH = "paid_search"
  ORGANIC_SEARCH = "organic_search"
  PAID_SOCIAL = "paid_social"
  ORGANIC_SOCIAL = "organic_social"
  EMAIL = "email"
  DISPLAY = "display"
  AFFILIATE = "affiliate"
  REFERRAL = "referral"
  VIDEO = "video"
  DIRECT = "direct"
  OTHER = "other"

  # All valid channel values
  ALL = [
    PAID_SEARCH,
    ORGANIC_SEARCH,
    PAID_SOCIAL,
    ORGANIC_SOCIAL,
    EMAIL,
    DISPLAY,
    AFFILIATE,
    REFERRAL,
    VIDEO,
    DIRECT,
    OTHER
  ].freeze

  # Domain pattern matching
  SEARCH_ENGINES = /google|bing|yahoo|duckduckgo|baidu/i
  SOCIAL_NETWORKS = /facebook|instagram|linkedin|twitter|tiktok|pinterest/i
  VIDEO_PLATFORMS = /youtube|vimeo/i
end
