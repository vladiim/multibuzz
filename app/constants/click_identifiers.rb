# frozen_string_literal: true

module ClickIdentifiers
  # =============================================================================
  # Google Ecosystem
  # =============================================================================
  GCLID = "gclid"      # Google Ads Click ID (Search, Display, Shopping, Video)
  GBRAID = "gbraid"    # Google iOS App Campaign (privacy-compliant)
  WBRAID = "wbraid"    # Google Web-to-App (privacy-compliant)
  DCLID = "dclid"      # DoubleClick/DV360 Display
  GCLSRC = "gclsrc"    # Google Ads source indicator (aw.ds for search ads)

  # =============================================================================
  # Microsoft Advertising
  # =============================================================================
  MSCLKID = "msclkid"  # Microsoft/Bing Ads Click ID

  # =============================================================================
  # Meta (Facebook/Instagram)
  # =============================================================================
  FBCLID = "fbclid"    # Facebook/Instagram Click ID

  # =============================================================================
  # TikTok
  # =============================================================================
  TTCLID = "ttclid"    # TikTok Click ID

  # =============================================================================
  # LinkedIn
  # =============================================================================
  LI_FAT_ID = "li_fat_id"  # LinkedIn First-Party Ad Tracking ID

  # =============================================================================
  # Twitter/X
  # =============================================================================
  TWCLID = "twclid"    # Twitter/X Click ID

  # =============================================================================
  # Pinterest
  # =============================================================================
  EPIK = "epik"        # Pinterest Click ID (also sets _epik cookie)

  # =============================================================================
  # Snapchat
  # =============================================================================
  SCLID = "sclid"      # Snapchat Click ID (lowercase variant)
  SCCLID = "ScCid"     # Snapchat Click ID (mixed case variant)

  # =============================================================================
  # Reddit
  # =============================================================================
  RDT_CID = "rdt_cid"  # Reddit Click ID

  # =============================================================================
  # Quora
  # =============================================================================
  QCLID = "qclid"      # Quora Click ID

  # =============================================================================
  # Yahoo/Verizon Media
  # =============================================================================
  VMCID = "vmcid"      # Yahoo DSP/Native Click ID

  # =============================================================================
  # Yandex (Russian search engine)
  # =============================================================================
  YCLID = "yclid"      # Yandex Direct Click ID

  # =============================================================================
  # Seznam (Czech search engine)
  # =============================================================================
  SZNCLID = "sznclid"  # Seznam/Sklik Click ID

  # =============================================================================
  # All supported click identifiers (URL parameters)
  # =============================================================================
  ALL = [
    # Google
    GCLID, GBRAID, WBRAID, DCLID, GCLSRC,
    # Microsoft
    MSCLKID,
    # Meta
    FBCLID,
    # TikTok
    TTCLID,
    # LinkedIn
    LI_FAT_ID,
    # Twitter/X
    TWCLID,
    # Pinterest
    EPIK,
    # Snapchat
    SCLID, SCCLID,
    # Reddit
    RDT_CID,
    # Quora
    QCLID,
    # Yahoo
    VMCID,
    # Yandex
    YCLID,
    # Seznam
    SZNCLID
  ].freeze

  # =============================================================================
  # Click ID → Source Mapping
  # Used to infer utm_source when not explicitly provided
  # =============================================================================
  SOURCE_MAP = {
    # Google
    GCLID => "google",
    GBRAID => "google",
    WBRAID => "google",
    DCLID => "google",
    GCLSRC => "google",
    # Microsoft
    MSCLKID => "microsoft",
    # Meta
    FBCLID => "facebook",
    # TikTok
    TTCLID => "tiktok",
    # LinkedIn
    LI_FAT_ID => "linkedin",
    # Twitter/X
    TWCLID => "twitter",
    # Pinterest
    EPIK => "pinterest",
    # Snapchat
    SCLID => "snapchat",
    SCCLID => "snapchat",
    # Reddit
    RDT_CID => "reddit",
    # Quora
    QCLID => "quora",
    # Yahoo
    VMCID => "yahoo",
    # Yandex
    YCLID => "yandex",
    # Seznam
    SZNCLID => "seznam"
  }.freeze

  # =============================================================================
  # Click ID → Channel Mapping
  # Used to determine marketing channel from click identifier
  # =============================================================================
  CHANNEL_MAP = {
    # Google - default to paid_search, but gclid can be display/video/shopping
    GCLID => Channels::PAID_SEARCH,
    GBRAID => Channels::PAID_SEARCH,
    WBRAID => Channels::PAID_SEARCH,
    DCLID => Channels::DISPLAY,
    GCLSRC => Channels::PAID_SEARCH,
    # Microsoft - search ads
    MSCLKID => Channels::PAID_SEARCH,
    # Social platforms - paid social
    FBCLID => Channels::PAID_SOCIAL,
    TTCLID => Channels::PAID_SOCIAL,
    LI_FAT_ID => Channels::PAID_SOCIAL,
    TWCLID => Channels::PAID_SOCIAL,
    EPIK => Channels::PAID_SOCIAL,
    SCLID => Channels::PAID_SOCIAL,
    SCCLID => Channels::PAID_SOCIAL,
    RDT_CID => Channels::PAID_SOCIAL,
    QCLID => Channels::PAID_SOCIAL,
    # Yahoo - can be search or native/display
    VMCID => Channels::PAID_SEARCH,
    # Regional search engines
    YCLID => Channels::PAID_SEARCH,
    SZNCLID => Channels::PAID_SEARCH
  }.freeze

  # =============================================================================
  # Google Places Click ID (Special Case)
  # Appears in utm_term as "plcid_NNNN" for Google Business Profile / Maps traffic
  # =============================================================================
  PLCID_PATTERN = /\Aplcid_\d+\z/.freeze

  def self.plcid_from_utm_term(utm_term)
    return nil if utm_term.blank?

    utm_term.match(PLCID_PATTERN)&.to_s
  end

  def self.plcid?(utm_term)
    plcid_from_utm_term(utm_term).present?
  end
end
