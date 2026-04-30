# frozen_string_literal: true

module AdPlatforms
  module Meta
    # --- OAuth ---
    AUTHORIZATION_URI = "https://www.facebook.com/v19.0/dialog/oauth"
    SCOPE = "ads_read"
    GRANT_AUTHORIZATION_CODE = "authorization_code"
    GRANT_FB_EXCHANGE = "fb_exchange_token"
    RESPONSE_TYPE_CODE = "code"

    # --- Graph API ---
    GRAPH_BASE_URL = "https://graph.facebook.com"
    API_VERSION = "v19.0"
    TOKEN_URI = URI("#{GRAPH_BASE_URL}/#{API_VERSION}/oauth/access_token").freeze
    AD_ACCOUNTS_URI = URI("#{GRAPH_BASE_URL}/#{API_VERSION}/me/adaccounts").freeze

    # --- Ad account fields ---
    AD_ACCOUNT_FIELDS = "id,name,currency,account_status,timezone_name"
    AD_ACCOUNT_STATUS_ACTIVE = 1

    # --- Insights fields ---
    INSIGHTS_FIELDS = "campaign_id,campaign_name,objective,spend,impressions,clicks,actions,action_values,date_start"
    INSIGHTS_LEVEL = "campaign"
    INSIGHTS_TIME_INCREMENT_DAILY = 1

    # --- Response keys ---
    FIELD_DATA = "data"
    FIELD_PAGING = "paging"
    FIELD_NEXT = "next"
    FIELD_ID = "id"
    FIELD_NAME = "name"
    FIELD_CURRENCY = "currency"
    FIELD_ACCOUNT_STATUS = "account_status"
    FIELD_TIMEZONE_NAME = "timezone_name"
    FIELD_ACCESS_TOKEN = "access_token"
    FIELD_EXPIRES_IN = "expires_in"
    FIELD_ERROR = "error"
    FIELD_ERROR_MESSAGE = "message"

    # --- Conversion action types we count by default ---
    PURCHASE_ACTION_TYPES = %w[purchase omni_purchase offsite_conversion.fb_pixel_purchase].freeze

    REDIRECT_URIS = {
      production: "https://mbuzz.co/oauth/meta_ads/callback",
      development: "http://localhost:3000/oauth/meta_ads/callback",
      test: "http://localhost:3000/oauth/meta_ads/callback"
    }.freeze

    def self.credentials
      Rails.application.credentials.meta_ads
    end

    def self.redirect_uri
      REDIRECT_URIS.fetch(Rails.env.to_sym)
    end
  end
end
