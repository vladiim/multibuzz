# frozen_string_literal: true

# Event property keys stored in events.properties JSONB column
# These are the standard dimensions extracted/enriched by the platform
module PropertyKeys
  # URL components (extracted from url field)
  URL = "url"
  HOST = "host"
  PATH = "path"
  QUERY_PARAMS = "query_params"

  # Referrer components (extracted from referrer field)
  REFERRER = "referrer"
  REFERRER_HOST = "referrer_host"
  REFERRER_PATH = "referrer_path"

  # UTM parameters (extracted from URL query string)
  # See UtmKeys module for individual UTM key constants
  UTM_SOURCE = UtmKeys::SOURCE
  UTM_MEDIUM = UtmKeys::MEDIUM
  UTM_CAMPAIGN = UtmKeys::CAMPAIGN
  UTM_CONTENT = UtmKeys::CONTENT
  UTM_TERM = UtmKeys::TERM

  # Attribution
  CHANNEL = "channel"

  # Funnel tracking
  FUNNEL = "funnel"
  FUNNEL_STEP = "funnel_step"
  FUNNEL_POSITION = "funnel_position"

  # Server-enriched metadata (nested under request_metadata key)
  REQUEST_METADATA = "request_metadata"

  # All property keys that are automatically extracted/enriched
  AUTO_EXTRACTED = [
    HOST,
    PATH,
    QUERY_PARAMS,
    REFERRER_HOST,
    REFERRER_PATH,
    UTM_SOURCE,
    UTM_MEDIUM,
    UTM_CAMPAIGN,
    UTM_CONTENT,
    UTM_TERM,
    CHANNEL,
    REQUEST_METADATA
  ].freeze

  # Property keys that should be indexed for fast querying
  INDEXED = [
    UTM_SOURCE,
    UTM_MEDIUM,
    UTM_CAMPAIGN,
    HOST,
    PATH
  ].freeze
end
