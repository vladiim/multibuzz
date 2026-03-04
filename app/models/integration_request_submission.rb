# frozen_string_literal: true

class IntegrationRequestSubmission < FormSubmission
  COMING_SOON_PLATFORMS = [
    "Meta Ads",
    "TikTok Ads",
    "LinkedIn Ads",
    "Microsoft Ads (Bing)",
    "Pinterest Ads",
    "Snapchat Ads",
    "Reddit Ads",
    "X (Twitter) Ads",
    "Apple Search Ads",
    "Phone/Call Tracking",
    "CSV Import"
  ].freeze

  REQUEST_ONLY_PLATFORMS = [
    "Amazon Ads",
    "Criteo",
    "The Trade Desk",
    "Other"
  ].freeze

  PLATFORM_OPTIONS = ([ "Google Ads" ] + COMING_SOON_PLATFORMS + REQUEST_ONLY_PLATFORMS).freeze

  MONTHLY_SPEND_OPTIONS = [
    "Under $1K",
    "$1K – $10K",
    "$10K – $50K",
    "$50K – $100K",
    "$100K+"
  ].freeze

  store_accessor :data, :platform_name, :platform_name_other,
                        :monthly_spend, :notes, :account_id, :plan_name

  include IntegrationRequestSubmission::Validations
end
