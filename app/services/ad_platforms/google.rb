# frozen_string_literal: true

module AdPlatforms
  module Google
    AUTHORIZATION_URI = "https://accounts.google.com/o/oauth2/v2/auth"
    TOKEN_URI = URI("https://oauth2.googleapis.com/token").freeze
    SCOPE = "https://www.googleapis.com/auth/adwords"
    GRANT_AUTHORIZATION_CODE = "authorization_code"
    GRANT_REFRESH_TOKEN = "refresh_token"
    RESPONSE_TYPE_CODE = "code"
    ACCESS_TYPE_OFFLINE = "offline"
    PROMPT_CONSENT = "consent"

    # --- Google Ads REST API ---
    API_VERSION = "v18"
    API_BASE_URL = "https://googleads.googleapis.com"
    LIST_CUSTOMERS_URI = URI("#{API_BASE_URL}/#{API_VERSION}/customers:listAccessibleCustomers").freeze
    SEARCH_PATH = "googleAds:search"
    CUSTOMER_QUERY = "SELECT customer.id, customer.descriptive_name, customer.currency_code, customer.manager FROM customer LIMIT 1"

    # --- API response fields ---
    FIELD_RESOURCE_NAMES = "resourceNames"
    FIELD_RESULTS = "results"
    FIELD_CUSTOMER = "customer"
    FIELD_ID = "id"
    FIELD_DESCRIPTIVE_NAME = "descriptiveName"
    FIELD_CURRENCY_CODE = "currencyCode"
    FIELD_MANAGER = "manager"

    # --- HTTP headers ---
    HEADER_DEVELOPER_TOKEN = "developer-token"

    REDIRECT_URIS = {
      production: "https://mbuzz.co/oauth/google_ads/callback",
      development: "http://localhost:3000/oauth/google_ads/callback",
      test: "http://localhost:3000/oauth/google_ads/callback"
    }.freeze

    def self.credentials
      Rails.application.credentials.google_ads
    end

    def self.redirect_uri
      REDIRECT_URIS.fetch(Rails.env.to_sym)
    end
  end
end
