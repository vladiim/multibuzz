# frozen_string_literal: true

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
  AI = "ai"
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
    AI,
    DIRECT,
    OTHER
  ].freeze

  # Hex colors — keep in sync with CHANNEL_COLORS in chart_controller.js
  COLORS = {
    PAID_SEARCH => "#6366F1",
    ORGANIC_SEARCH => "#10B981",
    PAID_SOCIAL => "#F59E0B",
    ORGANIC_SOCIAL => "#84CC16",
    EMAIL => "#EC4899",
    DISPLAY => "#8B5CF6",
    AFFILIATE => "#14B8A6",
    REFERRAL => "#F97316",
    VIDEO => "#EF4444",
    AI => "#06B6D4",
    DIRECT => "#6B7280",
    OTHER => "#9CA3AF"
  }.freeze

  # Domain pattern matching
  SEARCH_ENGINES = /google|bing|yahoo|duckduckgo|baidu|brave|\.goog$/i
  SOCIAL_NETWORKS = /facebook|instagram|linkedin|twitter|tiktok|pinterest|\bt\.co\b|threads/i
  VIDEO_PLATFORMS = /youtube|vimeo/i
  EMAIL_PROVIDERS = /\bwebmail\./i
  AI_ENGINES = /chatgpt|openai|perplexity|claude\.ai|gemini|copilot\.microsoft|meta\.ai|grok\.x\.ai|you\.com|phind|kagi/i
end
