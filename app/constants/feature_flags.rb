# frozen_string_literal: true

module FeatureFlags
  GOOGLE_ADS_INTEGRATION = "google_ads_integration"
  META_ADS_INTEGRATION = "meta_ads_integration"
  LINKEDIN_ADS_INTEGRATION = "linkedin_ads_integration"
  CONVERSION_FEEDBACK = "conversion_feedback"

  ALL = [
    GOOGLE_ADS_INTEGRATION,
    META_ADS_INTEGRATION,
    LINKEDIN_ADS_INTEGRATION,
    CONVERSION_FEEDBACK
  ].freeze
end
