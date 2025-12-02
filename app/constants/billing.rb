# frozen_string_literal: true

module Billing
  # --- Plan Slugs ---
  PLAN_FREE = "free"
  PLAN_STARTER = "starter"
  PLAN_GROWTH = "growth"
  PLAN_PRO = "pro"
  PLAN_ENTERPRISE = "enterprise"

  ALL_PLANS = [
    PLAN_FREE,
    PLAN_STARTER,
    PLAN_GROWTH,
    PLAN_PRO,
    PLAN_ENTERPRISE
  ].freeze

  PAID_PLANS = [
    PLAN_STARTER,
    PLAN_GROWTH,
    PLAN_PRO,
    PLAN_ENTERPRISE
  ].freeze

  # --- Pricing ---
  CENTS_PER_DOLLAR = 100
  EVENTS_PER_MILLION = 1_000_000
  EVENTS_PER_THOUSAND = 1_000
  OVERAGE_UNIT_SIZE = 10_000  # price is per 10K events

  # --- Plan Limits ---
  FREE_EVENT_LIMIT = 10_000
  STARTER_EVENT_LIMIT = 50_000
  GROWTH_EVENT_LIMIT = 250_000
  PRO_EVENT_LIMIT = 1_000_000

  # --- Plan Prices (cents) ---
  FREE_MONTHLY_PRICE_CENTS = 0
  STARTER_MONTHLY_PRICE_CENTS = 2900
  GROWTH_MONTHLY_PRICE_CENTS = 9900
  PRO_MONTHLY_PRICE_CENTS = 29900

  # --- Plan Sort Order ---
  FREE_SORT_ORDER = 0
  STARTER_SORT_ORDER = 1
  GROWTH_SORT_ORDER = 2
  PRO_SORT_ORDER = 3
  ENTERPRISE_SORT_ORDER = 4

  # --- Overage Prices (cents per 10K) ---
  STARTER_OVERAGE_CENTS = 580
  GROWTH_OVERAGE_CENTS = 396
  PRO_OVERAGE_CENTS = 299

  # --- Time Periods ---
  GRACE_PERIOD_DAYS = 3

  # Days after payment failure before account is suspended entirely
  SUSPENSION_DAYS = 30

  # Default trial duration
  DEFAULT_TRIAL_DAYS = 14

  # Usage alert thresholds (percentage)
  USAGE_WARNING_THRESHOLD = 80
  USAGE_LIMIT_THRESHOLD = 100

  # Days before expiry to show warning / send reminder
  FREE_UNTIL_WARNING_DAYS = 7
  FREE_UNTIL_FINAL_REMINDER_DAYS = 1
  TRIAL_REMINDER_DAYS = 3

  # Billing statuses
  FREE_FOREVER = "free_forever"
  FREE_UNTIL = "free_until"
  TRIALING = "trialing"
  ACTIVE = "active"
  PAST_DUE = "past_due"
  CANCELLED = "cancelled"
  EXPIRED = "expired"

  ALL_STATUSES = [
    FREE_FOREVER,
    FREE_UNTIL,
    TRIALING,
    ACTIVE,
    PAST_DUE,
    CANCELLED,
    EXPIRED
  ].freeze

  # Statuses that allow event ingestion
  INGESTION_ALLOWED_STATUSES = [
    FREE_FOREVER,
    FREE_UNTIL,
    TRIALING,
    ACTIVE,
    PAST_DUE  # allowed during grace/suspension period (may be locked)
  ].freeze

  # Banner types
  BANNER_PAST_DUE = :past_due
  BANNER_FREE_UNTIL_EXPIRING = :free_until_expiring
  BANNER_USAGE_LIMIT = :usage_limit
  BANNER_USAGE_WARNING = :usage_warning

  # --- Cache Keys ---
  USAGE_CACHE_KEY_PREFIX = "account:%{id}:usage:%{period}"

  # --- Display ---
  FREE_PRICE_LABEL = "Free"
  PRICE_FORMAT = "$%d/mo"
  EVENTS_MILLIONS_FORMAT = "%dM"
  EVENTS_THOUSANDS_FORMAT = "%dK"
end
