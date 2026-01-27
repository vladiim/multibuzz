# frozen_string_literal: true

module Sitemap
  # --- Change Frequencies ---
  CHANGEFREQ_DAILY = "daily"
  CHANGEFREQ_WEEKLY = "weekly"
  CHANGEFREQ_MONTHLY = "monthly"
  CHANGEFREQ_YEARLY = "yearly"

  # --- Priority Levels ---
  PRIORITY_HIGHEST = 1.0
  PRIORITY_HIGH = 0.9
  PRIORITY_MEDIUM_HIGH = 0.8
  PRIORITY_MEDIUM = 0.7
  PRIORITY_MEDIUM_LOW = 0.6
  PRIORITY_LOW = 0.5
  PRIORITY_LOWEST = 0.4

  # --- Article Priority Mapping ---
  ARTICLE_PRIORITY_MAP = {
    "P0" => PRIORITY_MEDIUM_HIGH,
    "P1" => PRIORITY_MEDIUM,
    "P2" => PRIORITY_MEDIUM_LOW,
    "P3" => PRIORITY_LOW
  }.freeze

  DEFAULT_ARTICLE_PRIORITY = PRIORITY_MEDIUM_LOW
end
