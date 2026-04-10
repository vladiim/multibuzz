# frozen_string_literal: true

module ConsentHelper
  # --- Consent geo gating ---
  #
  # Countries where we must show a consent banner before loading any
  # non-essential analytics or advertising tags. EU27 + non-EU EEA + UK + CH.
  # California is handled separately because CF-IPCountry returns the country
  # code for all US visitors and we need the region to disambiguate.
  CONSENT_COUNTRIES = %w[
    AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE
    GB IS LI NO CH
  ].freeze

  US_COUNTRY_CODE        = "US"
  CALIFORNIA_REGION_CODE = "CA"

  CF_COUNTRY_HEADER = "CF-IPCountry"
  CF_REGION_HEADER  = "CF-Region-Code"
  CF_UNKNOWN_VALUES = %w[XX T1].freeze

  CONSENT_DENIED  = "denied"
  CONSENT_GRANTED = "granted"

  GTM_CREDENTIALS_NAMESPACE = :gtm
  GTM_CONTAINER_ID_KEY      = :container_id

  def gtm_container_id
    Rails.application.credentials.dig(GTM_CREDENTIALS_NAMESPACE, GTM_CONTAINER_ID_KEY).presence
  end

  def gtm_enabled?
    gtm_container_id.present?
  end

  def visitor_country(request)
    cf_country(request) || geocoded_country(request)
  end

  def visitor_region(request)
    request.headers[CF_REGION_HEADER].presence&.upcase
  end

  def requires_consent_banner?(request)
    visitor_country(request).then { |country| eea_or_unknown?(country) || california_visitor?(country, request) }
  end

  def consent_default_state(request)
    requires_consent_banner?(request) ? CONSENT_DENIED : CONSENT_GRANTED
  end

  private

  def eea_or_unknown?(country)
    country.nil? || CONSENT_COUNTRIES.include?(country)
  end

  def california_visitor?(country, request)
    country == US_COUNTRY_CODE && visitor_region(request) == CALIFORNIA_REGION_CODE
  end

  def cf_country(request)
    value = request.headers[CF_COUNTRY_HEADER].presence&.upcase
    return nil if value.nil? || CF_UNKNOWN_VALUES.include?(value)
    value
  end

  def geocoded_country(request)
    Geocoder.search(request.remote_ip).first&.country_code&.upcase
  rescue StandardError
    nil
  end
end
