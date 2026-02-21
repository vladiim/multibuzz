# frozen_string_literal: true

module ReferrerSources
  module DataOrigins
    MATOMO_SEARCH = "matomo_search"
    MATOMO_SOCIAL = "matomo_social"
    MATOMO_SPAM = "matomo_spam"
    SNOWPLOW = "snowplow"
    CUSTOM = "custom"

    ALL = [
      MATOMO_SEARCH,
      MATOMO_SOCIAL,
      MATOMO_SPAM,
      SNOWPLOW,
      CUSTOM
    ].freeze

    # Priority for conflict resolution (higher = preferred)
    PRIORITY = {
      CUSTOM => 5,
      MATOMO_SEARCH => 3,
      MATOMO_SOCIAL => 3,
      MATOMO_SPAM => 3,
      SNOWPLOW => 1
    }.freeze
  end
end
