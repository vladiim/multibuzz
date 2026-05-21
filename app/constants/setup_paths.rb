# frozen_string_literal: true

# How the customer chose to set up mbuzz, recorded on Account#setup_path.
# Used by the onboarding controller to route, by views to render the
# setup-choice cards, and by the Account enum that backs the column.
module SetupPaths
  SELF_SERVE = "self_serve"
  TEAMMATE = "teammate"
  ASSISTED = "assisted"

  ALL = [ SELF_SERVE, TEAMMATE, ASSISTED ].freeze

  # Integer mapping for the Account#setup_path enum (DB stores integers).
  ENUM_VALUES = {
    SELF_SERVE => 0,
    TEAMMATE => 1,
    ASSISTED => 2
  }.freeze
end
