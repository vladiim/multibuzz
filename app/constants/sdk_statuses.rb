# frozen_string_literal: true

module SdkStatuses
  LIVE = "live"
  BETA = "beta"
  COMING_SOON = "coming_soon"

  ALL = [ LIVE, BETA, COMING_SOON ].freeze

  BADGES = {
    LIVE => "Live",
    BETA => "Beta",
    COMING_SOON => "Coming Soon"
  }.freeze
end
