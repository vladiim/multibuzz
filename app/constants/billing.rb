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

  # --- Plan Limits (Single Source of Truth) ---
  FREE_EVENT_LIMIT = 30_000
  STARTER_EVENT_LIMIT = 1_000_000
  GROWTH_EVENT_LIMIT = 5_000_000
  PRO_EVENT_LIMIT = 25_000_000

  # Consolidated plan limits hash - use this for lookups
  PLAN_LIMITS = {
    PLAN_FREE => FREE_EVENT_LIMIT,
    PLAN_STARTER => STARTER_EVENT_LIMIT,
    PLAN_GROWTH => GROWTH_EVENT_LIMIT,
    PLAN_PRO => PRO_EVENT_LIMIT
  }.freeze

  # --- Overage Block Sizes ---
  # Each tier has a different block size for overage billing
  STARTER_OVERAGE_BLOCK_SIZE = 250_000
  GROWTH_OVERAGE_BLOCK_SIZE = 1_000_000
  PRO_OVERAGE_BLOCK_SIZE = 5_000_000

  # Legacy constant for backwards compatibility
  OVERAGE_UNIT_SIZE = 10_000  # deprecated, use tier-specific block sizes

  # --- Custom Attribution Model Limits ---
  CUSTOM_MODEL_LIMITS = {
    PLAN_FREE => 0,
    PLAN_STARTER => 3,
    PLAN_GROWTH => 5,
    PLAN_PRO => 10
  }.freeze

  # --- Ad Platform Connection Limits ---
  # nil = unlimited (Pro, Enterprise). Free is 0 (gated by can_connect_ad_platform?).
  AD_PLATFORM_CONNECTION_LIMITS = {
    PLAN_FREE => 0,
    PLAN_STARTER => 2,
    PLAN_GROWTH => 5,
    PLAN_PRO => nil,
    PLAN_ENTERPRISE => nil
  }.freeze

  # --- Attribution Rerun Limits (matches event limits) ---
  RERUN_LIMITS = PLAN_LIMITS

  # --- Rerun Overage (event_overage / 7, in cents per block) ---
  # Starter: $5/250K block / 7 = ~$0.71
  # Growth: $15/1M block / 7 = ~$2.14
  # Pro: $50/5M block / 7 = ~$7.14
  RERUN_OVERAGE_CENTS = {
    PLAN_STARTER => 71,
    PLAN_GROWTH => 214,
    PLAN_PRO => 714
  }.freeze

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

  # --- Overage Prices (cents per block) ---
  # Starter: $5 per 250K block
  # Growth: $15 per 1M block
  # Pro: $50 per 5M block
  STARTER_OVERAGE_CENTS = 500
  GROWTH_OVERAGE_CENTS = 1500
  PRO_OVERAGE_CENTS = 5000

  # Overage block sizes by plan (for convenience)
  OVERAGE_BLOCK_SIZES = {
    PLAN_STARTER => STARTER_OVERAGE_BLOCK_SIZE,
    PLAN_GROWTH => GROWTH_OVERAGE_BLOCK_SIZE,
    PLAN_PRO => PRO_OVERAGE_BLOCK_SIZE
  }.freeze

  OVERAGE_PRICES_CENTS = {
    PLAN_STARTER => STARTER_OVERAGE_CENTS,
    PLAN_GROWTH => GROWTH_OVERAGE_CENTS,
    PLAN_PRO => PRO_OVERAGE_CENTS
  }.freeze

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

  # --- Stripe Subscription Statuses ---
  STRIPE_STATUS_ACTIVE = "active"
  STRIPE_STATUS_TRIALING = "trialing"
  STRIPE_STATUS_PAST_DUE = "past_due"
  STRIPE_STATUS_CANCELED = "canceled"
  STRIPE_STATUS_UNPAID = "unpaid"

  # Map Stripe subscription status to our billing status
  STRIPE_STATUS_MAP = {
    STRIPE_STATUS_ACTIVE => :active,
    STRIPE_STATUS_TRIALING => :trialing,
    STRIPE_STATUS_PAST_DUE => :past_due,
    STRIPE_STATUS_CANCELED => :cancelled,
    STRIPE_STATUS_UNPAID => :cancelled
  }.freeze
end
