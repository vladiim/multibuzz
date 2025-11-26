# frozen_string_literal: true

module AttributionAlgorithms
  # Single-touch models
  FIRST_TOUCH = "first_touch"
  LAST_TOUCH = "last_touch"

  # Multi-touch models
  LINEAR = "linear"
  TIME_DECAY = "time_decay"
  U_SHAPED = "u_shaped"
  W_SHAPED = "w_shaped"
  PARTICIPATION = "participation"

  # Default lookback window for attribution calculations
  DEFAULT_LOOKBACK_DAYS = 30

  # All algorithms (non-data-science, rule-based)
  ALL = [
    FIRST_TOUCH,
    LAST_TOUCH,
    LINEAR,
    TIME_DECAY,
    U_SHAPED,
    W_SHAPED,
    PARTICIPATION
  ].freeze

  # Algorithms with implemented classes
  IMPLEMENTED = [
    FIRST_TOUCH,
    LAST_TOUCH,
    LINEAR
  ].freeze

  # Default models created for new accounts (only implemented ones)
  DEFAULTS = IMPLEMENTED.freeze
end
