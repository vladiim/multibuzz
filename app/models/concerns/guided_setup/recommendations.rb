# frozen_string_literal: true

module GuidedSetup::Recommendations
  extend ActiveSupport::Concern

  # The specialist works the integration the customer already runs. Meta wins
  # ties because mbuzz's Meta CAPI flow is the most-used path and sets the
  # default value moment fastest; Google Ads is the fallback, and sGTM is only
  # picked when the customer isn't running paid ads but is installing via sGTM.
  INTEGRATION_PRIORITY = %w[meta google_ads].freeze
  INTEGRATION_TARGET_NONE = "none"
  INTEGRATION_TARGET_SGTM = "sgtm"

  class_methods do
    def integration_target_for(setup_profile)
      profile = setup_profile || {}
      ad_platforms = Array(profile["ad_platforms"] || profile[:ad_platforms])
      install_platforms = Array(profile["install_platforms"] || profile[:install_platforms])

      INTEGRATION_PRIORITY.find { |p| ad_platforms.include?(p) } ||
        (install_platforms.include?(INTEGRATION_TARGET_SGTM) ? INTEGRATION_TARGET_SGTM : INTEGRATION_TARGET_NONE)
    end
  end
end
