# frozen_string_literal: true

# Path patterns that must never load marketing analytics tags (GA4, Google
# Ads, Meta Pixel). This is the safety net for the explicit
# `skip_marketing_analytics` controller opt-out — anything that slips
# through the explicit list is caught here by URL shape.
#
# We deliberately do NOT block `acct_*`, `user_*`, or `sess_*` prefix IDs
# because they appear in normal authenticated routes that the team wants
# instrumented in GA4. URL scrubbing of those identifiers happens in the
# GTM tag config, not here.
module SensitivePaths
  ADMIN_NAMESPACE          = %r{\A/admin(/|\z)}
  API_KEYS_ROUTE           = %r{\A/accounts/[^/]+/api_keys}
  BILLING_ROUTE            = %r{\A/accounts/[^/]+/billing}
  INTEGRATIONS_ROUTE       = %r{\A/accounts/[^/]+/integrations}
  ONBOARDING_API_KEY_PAGES = %r{\A/onboarding/(install|setup)(/|\z)}
  IDENTITIES_ROUTE         = %r{\A/dashboard/identities}
  CONVERSION_DETAIL        = %r{\A/dashboard/conversion_detail}
  EXPORTS_ROUTE            = %r{\A/dashboard/exports}
  EDIT_ACTION              = %r{/edit\z}
  API_KEY_LITERAL          = /sk_(live|test)_/
  VISITOR_PREFIX_ID        = /\bvis_[a-z0-9]{8,}/
  IDENTITY_PREFIX_ID       = /\bidt_[a-z0-9]{8,}/
  CREDENTIAL_PREFIX_ID     = /\bcred_[a-z0-9]{8,}/

  PATTERNS = [
    ADMIN_NAMESPACE,
    API_KEYS_ROUTE,
    BILLING_ROUTE,
    INTEGRATIONS_ROUTE,
    ONBOARDING_API_KEY_PAGES,
    IDENTITIES_ROUTE,
    CONVERSION_DETAIL,
    EXPORTS_ROUTE,
    EDIT_ACTION,
    API_KEY_LITERAL,
    VISITOR_PREFIX_ID,
    IDENTITY_PREFIX_ID,
    CREDENTIAL_PREFIX_ID
  ].freeze

  def self.match?(path)
    PATTERNS.any? { |pattern| pattern.match?(path) }
  end
end
