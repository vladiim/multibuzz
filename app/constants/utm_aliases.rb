# frozen_string_literal: true

module UtmAliases
  # Source aliases → canonical name
  SOURCES = {
    "fb" => "facebook",
    "ig" => "instagram",
    "tw" => "twitter",
    "x" => "twitter",
    "li" => "linkedin",
    "yt" => "youtube",
    "goog" => "google",
    "bing" => "microsoft",
    "msn" => "microsoft"
  }.freeze

  # Canonical sources for fuzzy matching
  CANONICAL_SOURCES = %w[
    facebook instagram twitter linkedin youtube google microsoft
    pinterest snapchat tiktok reddit whatsapp telegram
  ].freeze

  # Medium aliases → canonical medium
  MEDIUMS = {
    # paid search
    "cpc" => "cpc",
    "ppc" => "cpc",
    "paidsearch" => "cpc",
    "paid_search" => "cpc",
    "paid-search" => "cpc",
    "sem" => "cpc",
    "adwords" => "cpc",
    # paid social
    "paid_social" => "paid_social",
    "paid-social" => "paid_social",
    "paidsocial" => "paid_social",
    "cpm-social" => "paid_social",
    "cpm_social" => "paid_social",
    # social
    "social" => "social",
    "social-media" => "social",
    "social_media" => "social",
    "sm" => "social",
    # email
    "email" => "email",
    "e-mail" => "email",
    "e_mail" => "email",
    "newsletter" => "email",
    # display
    "display" => "display",
    "banner" => "display",
    "gdn" => "display",
    "programmatic" => "display",
    # video
    "video" => "video",
    "cpv" => "video",
    # affiliate
    "affiliate" => "affiliate",
    "affiliates" => "affiliate",
    "partner" => "affiliate",
    # organic
    "organic" => "organic",
    # referral
    "referral" => "referral"
  }.freeze
end
