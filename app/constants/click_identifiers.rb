# frozen_string_literal: true

module ClickIdentifiers
  # Google Ads
  GCLID = "gclid"      # Google Click ID
  GBRAID = "gbraid"    # Google iOS App Campaign
  WBRAID = "wbraid"    # Google Web-to-App
  DCLID = "dclid"      # DoubleClick/DV360

  # Microsoft Ads
  MSCLKID = "msclkid"  # Microsoft Click ID

  # Meta (Facebook/Instagram)
  FBCLID = "fbclid"    # Facebook Click ID

  # TikTok
  TTCLID = "ttclid"    # TikTok Click ID

  # LinkedIn
  LI_FAT_ID = "li_fat_id"  # LinkedIn First-Party Ad Tracking

  # Twitter/X
  TWCLID = "twclid"    # Twitter Click ID

  # Pinterest
  EPIK = "epik"        # Pinterest Click ID

  # Snapchat
  SCLID = "sclid"      # Snapchat Click ID

  # All supported click identifiers
  ALL = [
    GCLID, GBRAID, WBRAID, DCLID,
    MSCLKID,
    FBCLID,
    TTCLID,
    LI_FAT_ID,
    TWCLID,
    EPIK,
    SCLID
  ].freeze

  # Click ID → implied source mapping
  SOURCE_MAP = {
    GCLID => "google",
    GBRAID => "google",
    WBRAID => "google",
    DCLID => "google",
    MSCLKID => "microsoft",
    FBCLID => "facebook",
    TTCLID => "tiktok",
    LI_FAT_ID => "linkedin",
    TWCLID => "twitter",
    EPIK => "pinterest",
    SCLID => "snapchat"
  }.freeze

  # Click ID → implied channel mapping
  CHANNEL_MAP = {
    GCLID => Channels::PAID_SEARCH,
    GBRAID => Channels::PAID_SEARCH,
    WBRAID => Channels::PAID_SEARCH,
    DCLID => Channels::DISPLAY,
    MSCLKID => Channels::PAID_SEARCH,
    FBCLID => Channels::PAID_SOCIAL,
    TTCLID => Channels::PAID_SOCIAL,
    LI_FAT_ID => Channels::PAID_SOCIAL,
    TWCLID => Channels::PAID_SOCIAL,
    EPIK => Channels::PAID_SOCIAL,
    SCLID => Channels::PAID_SOCIAL
  }.freeze
end
