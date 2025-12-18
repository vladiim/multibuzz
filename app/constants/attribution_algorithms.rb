# frozen_string_literal: true

module AttributionAlgorithms
  # Single-touch models
  FIRST_TOUCH = "first_touch"
  LAST_TOUCH = "last_touch"

  # Multi-touch models
  LINEAR = "linear"
  TIME_DECAY = "time_decay"
  U_SHAPED = "u_shaped"
  PARTICIPATION = "participation"

  # Probabilistic models (data-driven, no training required)
  MARKOV_CHAIN = "markov_chain"
  SHAPLEY_VALUE = "shapley_value"

  # Journey position (for funnel segmentation)
  ASSISTED = "assisted"

  # Default lookback window for attribution calculations
  DEFAULT_LOOKBACK_DAYS = 30

  # Tier 1: Heuristic models (rule-based, always available)
  HEURISTIC = [
    FIRST_TOUCH,
    LAST_TOUCH,
    LINEAR,
    TIME_DECAY,
    U_SHAPED,
    PARTICIPATION
  ].freeze

  # Tier 2: Probabilistic models (data-driven, no training required)
  PROBABILISTIC = [
    MARKOV_CHAIN,
    SHAPLEY_VALUE
  ].freeze

  # All implemented algorithms
  IMPLEMENTED = (HEURISTIC + PROBABILISTIC).freeze

  # Default models created for new accounts (Tier 1 + Tier 2 per pricing spec)
  DEFAULTS = IMPLEMENTED.freeze

  # Legacy alias for backwards compatibility
  ALL = HEURISTIC.freeze

  # Journey positions for funnel segmentation (where channel appears in journey)
  JOURNEY_POSITIONS = [
    FIRST_TOUCH,
    LAST_TOUCH,
    ASSISTED
  ].freeze

  DEFAULT_JOURNEY_POSITION = LAST_TOUCH
end
