# frozen_string_literal: true

module Account::Billing
  extend ActiveSupport::Concern

  included do
    belongs_to :plan, optional: true
    has_many :billing_events, dependent: :destroy

    enum :billing_status, {
      free_forever: 0,
      free_until: 1,
      trialing: 2,
      active: 3,
      past_due: 4,
      cancelled: 5,
      expired: 6
    }, prefix: :billing

    scope :billing_active, -> { where(billing_status: [ :free_forever, :free_until, :trialing, :active ]) }
    scope :past_due, -> { where(billing_status: :past_due) }
    scope :with_expiring_free_until, ->(days_from_now) {
      where(billing_status: :free_until)
        .where("free_until <= ?", days_from_now.days.from_now)
        .where("free_until > ?", Time.current)
    }
  end

  # --- State Predicates ---

  def can_ingest_events?
    return false if billing_cancelled? || billing_expired?
    return within_free_limit? if billing_free_forever?
    return free_until_valid? if billing_free_until?
    return true if billing_trialing? || billing_active?
    return within_grace_period? || within_suspension_period? if billing_past_due?

    false
  end

  def should_lock_events?
    billing_past_due? && !within_grace_period?
  end

  def within_grace_period?
    return false unless billing_past_due? && grace_period_ends_at.present?

    Time.current < grace_period_ends_at
  end

  def within_suspension_period?
    return false unless billing_past_due? && payment_failed_at.present?

    Time.current < payment_failed_at + ::Billing::SUSPENSION_DAYS.days
  end

  def free_until_valid?
    billing_free_until? && free_until.present? && free_until > Time.current
  end

  def events_locked?
    billing_past_due? && !within_grace_period?
  end

  # --- Usage Tracking ---

  def within_free_limit?
    current_period_usage < free_event_limit
  end

  def free_event_limit
    plan&.events_included || ::Billing::FREE_EVENT_LIMIT
  end

  def current_period_usage
    Rails.cache.read(usage_cache_key).to_i
  end

  def increment_usage!(count = 1)
    Rails.cache.increment(usage_cache_key, count)
  end

  def usage_cache_key
    format(::Billing::USAGE_CACHE_KEY_PREFIX, id: id, period: current_billing_period)
  end

  def current_billing_period
    (current_period_start || created_at).strftime("%Y-%m")
  end

  def usage_percentage
    return 0 if free_event_limit.zero?

    [ (current_period_usage.to_f / free_event_limit * ::Billing::USAGE_LIMIT_THRESHOLD).round, ::Billing::USAGE_LIMIT_THRESHOLD ].min
  end

  def approaching_limit?
    usage_percentage >= ::Billing::USAGE_WARNING_THRESHOLD
  end

  def at_limit?
    usage_percentage >= ::Billing::USAGE_LIMIT_THRESHOLD
  end

  # --- Billing Actions ---

  def start_trial!(plan:, ends_at: ::Billing::DEFAULT_TRIAL_DAYS.days.from_now)
    update!(
      plan: plan,
      billing_status: :trialing,
      trial_ends_at: ends_at,
      current_period_start: Time.current,
      current_period_end: ends_at
    )
  end

  def activate_subscription!(stripe_subscription_id:, period_start:, period_end:)
    update!(
      billing_status: :active,
      stripe_subscription_id: stripe_subscription_id,
      subscription_started_at: Time.current,
      current_period_start: period_start,
      current_period_end: period_end,
      payment_failed_at: nil,
      grace_period_ends_at: nil
    )
  end

  def mark_past_due!
    update!(
      billing_status: :past_due,
      payment_failed_at: Time.current,
      grace_period_ends_at: ::Billing::GRACE_PERIOD_DAYS.days.from_now
    )
  end

  def restore_from_past_due!
    update!(
      billing_status: :active,
      payment_failed_at: nil,
      grace_period_ends_at: nil
    )
  end

  def cancel_subscription!
    update!(
      billing_status: :cancelled,
      stripe_subscription_id: nil
    )
  end

  def expire!
    update!(billing_status: :expired)
  end

  def grant_free_until!(until_date:, plan: nil)
    update!(
      billing_status: :free_until,
      free_until: until_date,
      plan: plan || self.plan
    )
  end

  def extend_free_until!(until_date:)
    return unless billing_free_until?

    update!(free_until: until_date)
  end

  # --- Stripe ---

  def has_stripe_customer?
    stripe_customer_id.present?
  end

  def has_active_subscription?
    stripe_subscription_id.present? && billing_active?
  end

  # --- Banner Display ---

  def billing_banner_type
    return ::Billing::BANNER_PAST_DUE if billing_past_due?
    return ::Billing::BANNER_FREE_UNTIL_EXPIRING if billing_free_until? && free_until_expiring_soon?
    return ::Billing::BANNER_USAGE_LIMIT if billing_free_forever? && at_limit?
    return ::Billing::BANNER_USAGE_WARNING if billing_free_forever? && approaching_limit?

    nil
  end

  def free_until_expiring_soon?
    billing_free_until? && free_until.present? && free_until <= ::Billing::FREE_UNTIL_WARNING_DAYS.days.from_now
  end

  def days_until_free_expires
    return nil unless free_until.present?

    ((free_until - Time.current) / 1.day).ceil
  end

  # --- Ad Platform Connections ---

  def can_connect_ad_platform?
    ::Billing::PAID_PLANS.include?(plan&.slug)
  end

  def ad_platform_connection_limit
    return 0 if plan.nil?
    plan.ad_platform_connection_limit
  end

  def ad_platform_connections_used
    ad_platform_connections.where.not(status: :disconnected).count
  end

  def ad_platform_connections_remaining
    return Float::INFINITY if ad_platform_connections_unlimited?
    [ ad_platform_connection_limit.to_i - ad_platform_connections_used, 0 ].max
  end

  def ad_platform_connections_unlimited?
    can_connect_ad_platform? && ad_platform_connection_limit.nil?
  end

  def can_add_ad_platform_connection?
    can_connect_ad_platform? && ad_platform_connections_remaining > 0
  end

  # --- Attribution Model Limits ---

  def custom_model_limit
    plan_slug = plan&.slug || ::Billing::PLAN_FREE
    ::Billing::CUSTOM_MODEL_LIMITS.fetch(plan_slug, 0)
  end

  def custom_models_count
    attribution_models.custom.count
  end

  def can_create_custom_model?
    custom_models_count < custom_model_limit
  end

  def can_edit_full_aml?
    plan_slug = plan&.slug || ::Billing::PLAN_FREE
    ::Billing::PAID_PLANS.include?(plan_slug)
  end

  # --- Attribution Rerun Limits ---

  def rerun_limit
    plan_slug = plan&.slug || ::Billing::PLAN_FREE
    ::Billing::RERUN_LIMITS.fetch(plan_slug, ::Billing::RERUN_LIMITS[::Billing::PLAN_FREE])
  end

  def reruns_remaining
    [ rerun_limit - reruns_used_this_period, 0 ].max
  end

  def rerun_overage_cents
    plan_slug = plan&.slug || ::Billing::PLAN_FREE
    ::Billing::RERUN_OVERAGE_CENTS.fetch(plan_slug, 0)
  end

  def rerun_overage_block_size
    plan_slug = plan&.slug || ::Billing::PLAN_FREE
    ::Billing::OVERAGE_BLOCK_SIZES.fetch(plan_slug, ::Billing::STARTER_OVERAGE_BLOCK_SIZE)
  end

  def can_rerun_without_overage?(count)
    count <= reruns_remaining
  end

  def calculate_rerun_overage(count)
    return { covered: count, overage: 0, blocks: 0, cost_cents: 0, block_size: rerun_overage_block_size } if count <= reruns_remaining

    covered = reruns_remaining
    overage = count - covered
    blocks = (overage.to_f / rerun_overage_block_size).ceil
    cost_cents = blocks * rerun_overage_cents

    { covered: covered, overage: overage, blocks: blocks, cost_cents: cost_cents, block_size: rerun_overage_block_size }
  end

  def increment_reruns_used!(count)
    increment!(:reruns_used_this_period, count)
  end

  def reset_reruns_used!
    update!(reruns_used_this_period: 0)
  end
end
