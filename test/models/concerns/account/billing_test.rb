# frozen_string_literal: true

require "test_helper"

class Account::BillingTest < ActiveSupport::TestCase
  # --- Billing Status Enum ---

  test "should default to free_forever billing status" do
    new_account = Account.new(name: "Test", slug: "test-billing-#{SecureRandom.hex(4)}")

    assert_predicate new_account, :billing_free_forever?
  end

  test "should have all billing statuses" do
    statuses = %w[free_forever free_until trialing active past_due cancelled expired]

    statuses.each do |status|
      assert Account.billing_statuses.key?(status), "Missing billing status: #{status}"
    end
  end

  # --- can_ingest_events? ---

  test "can_ingest_events? returns true for free_forever within limit" do
    account.update!(billing_status: :free_forever, plan: free_plan)
    Rails.cache.write(account.usage_cache_key, 5000)

    assert_predicate account, :can_ingest_events?
  end

  test "can_ingest_events? returns false for free_forever at limit" do
    account.update!(billing_status: :free_forever, plan: free_plan)
    Rails.cache.write(account.usage_cache_key, Billing::FREE_EVENT_LIMIT)

    assert_not account.can_ingest_events?
  end

  test "can_ingest_events? returns true for free_until before expiry" do
    account.update!(
      billing_status: :free_until,
      free_until: 7.days.from_now,
      plan: starter_plan
    )

    assert_predicate account, :can_ingest_events?
  end

  test "can_ingest_events? returns false for free_until after expiry" do
    account.update!(
      billing_status: :free_until,
      free_until: 1.day.ago,
      plan: starter_plan
    )

    assert_not account.can_ingest_events?
  end

  test "can_ingest_events? returns true for trialing" do
    account.update!(
      billing_status: :trialing,
      trial_ends_at: 14.days.from_now,
      plan: starter_plan
    )

    assert_predicate account, :can_ingest_events?
  end

  test "can_ingest_events? returns true for active" do
    account.update!(billing_status: :active, plan: starter_plan)

    assert_predicate account, :can_ingest_events?
  end

  test "can_ingest_events? returns true for past_due within grace period" do
    account.update!(
      billing_status: :past_due,
      payment_failed_at: 1.day.ago,
      grace_period_ends_at: 2.days.from_now,
      plan: starter_plan
    )

    assert_predicate account, :can_ingest_events?
  end

  test "can_ingest_events? returns true for past_due within suspension period" do
    account.update!(
      billing_status: :past_due,
      payment_failed_at: 5.days.ago,
      grace_period_ends_at: 2.days.ago,
      plan: starter_plan
    )

    assert_predicate account, :can_ingest_events?
  end

  test "can_ingest_events? returns false for past_due after suspension period" do
    account.update!(
      billing_status: :past_due,
      payment_failed_at: 35.days.ago,
      grace_period_ends_at: 32.days.ago,
      plan: starter_plan
    )

    assert_not account.can_ingest_events?
  end

  test "can_ingest_events? returns false for cancelled" do
    account.update!(billing_status: :cancelled)

    assert_not account.can_ingest_events?
  end

  test "can_ingest_events? returns false for expired" do
    account.update!(billing_status: :expired)

    assert_not account.can_ingest_events?
  end

  # --- should_lock_events? ---

  test "should_lock_events? returns false within grace period" do
    account.update!(
      billing_status: :past_due,
      payment_failed_at: 1.day.ago,
      grace_period_ends_at: 2.days.from_now
    )

    assert_not account.should_lock_events?
  end

  test "should_lock_events? returns true after grace period" do
    account.update!(
      billing_status: :past_due,
      payment_failed_at: 5.days.ago,
      grace_period_ends_at: 2.days.ago
    )

    assert_predicate account, :should_lock_events?
  end

  test "should_lock_events? returns false for non-past_due statuses" do
    account.update!(billing_status: :active)

    assert_not account.should_lock_events?

    account.update!(billing_status: :trialing)

    assert_not account.should_lock_events?
  end

  # --- Usage Tracking ---

  test "current_period_usage returns cached value" do
    Rails.cache.write(account.usage_cache_key, 1234)

    assert_equal 1234, account.current_period_usage
  end

  test "current_period_usage returns 0 when cache empty" do
    Rails.cache.delete(account.usage_cache_key)

    assert_equal 0, account.current_period_usage
  end

  test "increment_usage! increments cache value" do
    Rails.cache.write(account.usage_cache_key, 100)

    account.increment_usage!(5)

    assert_equal 105, account.current_period_usage
  end

  test "usage_percentage calculates correctly" do
    account.update!(plan: free_plan)
    limit = Billing::FREE_EVENT_LIMIT
    Rails.cache.write(account.usage_cache_key, (limit * 0.8).to_i)

    assert_equal 80, account.usage_percentage
  end

  test "approaching_limit? returns true at 80%" do
    account.update!(plan: free_plan)
    limit = Billing::FREE_EVENT_LIMIT
    Rails.cache.write(account.usage_cache_key, (limit * 0.8).to_i)

    assert_predicate account, :approaching_limit?
  end

  test "approaching_limit? returns false below 80%" do
    account.update!(plan: free_plan)
    limit = Billing::FREE_EVENT_LIMIT
    Rails.cache.write(account.usage_cache_key, (limit * 0.7).to_i)

    assert_not account.approaching_limit?
  end

  test "at_limit? returns true at 100%" do
    account.update!(plan: free_plan)
    Rails.cache.write(account.usage_cache_key, Billing::FREE_EVENT_LIMIT)

    assert_predicate account, :at_limit?
  end

  # --- Billing Actions ---

  test "start_trial! sets trial state" do
    account.start_trial!(plan: starter_plan, ends_at: 14.days.from_now)

    assert_predicate account, :billing_trialing?
    assert_equal starter_plan, account.plan
    assert_predicate account.trial_ends_at, :present?
    assert_predicate account.current_period_start, :present?
  end

  test "activate_subscription! sets active state" do
    account.activate_subscription!(
      stripe_subscription_id: "sub_123",
      period_start: Time.current,
      period_end: 30.days.from_now
    )

    assert_predicate account, :billing_active?
    assert_equal "sub_123", account.stripe_subscription_id
    assert_nil account.payment_failed_at
    assert_nil account.grace_period_ends_at
  end

  test "mark_past_due! sets past_due state with grace period" do
    account.mark_past_due!

    assert_predicate account, :billing_past_due?
    assert_predicate account.payment_failed_at, :present?
    assert_predicate account.grace_period_ends_at, :present?
    assert_operator account.grace_period_ends_at, :>, Time.current
  end

  test "restore_from_past_due! clears failure state" do
    account.update!(
      billing_status: :past_due,
      payment_failed_at: 5.days.ago,
      grace_period_ends_at: 2.days.ago
    )

    account.restore_from_past_due!

    assert_predicate account, :billing_active?
    assert_nil account.payment_failed_at
    assert_nil account.grace_period_ends_at
  end

  test "cancel_subscription! sets cancelled state" do
    account.update!(stripe_subscription_id: "sub_123")

    account.cancel_subscription!

    assert_predicate account, :billing_cancelled?
    assert_nil account.stripe_subscription_id
  end

  test "expire! sets expired state" do
    account.update!(billing_status: :free_until, free_until: 1.day.ago)

    account.expire!

    assert_predicate account, :billing_expired?
  end

  test "grant_free_until! sets free_until state" do
    account.grant_free_until!(until_date: 90.days.from_now, plan: growth_plan)

    assert_predicate account, :billing_free_until?
    assert_equal growth_plan, account.plan
    assert_operator account.free_until, :>, 89.days.from_now
  end

  test "extend_free_until! extends existing free_until" do
    account.update!(billing_status: :free_until, free_until: 30.days.from_now)

    account.extend_free_until!(until_date: 90.days.from_now)

    assert_operator account.free_until, :>, 89.days.from_now
  end

  test "extend_free_until! does nothing if not free_until status" do
    account.update!(billing_status: :active, free_until: nil)

    account.extend_free_until!(until_date: 90.days.from_now)

    assert_nil account.free_until
  end

  # --- Stripe ---

  test "has_stripe_customer? returns true when customer_id present" do
    account.update!(stripe_customer_id: "cus_123")

    assert_predicate account, :has_stripe_customer?
  end

  test "has_stripe_customer? returns false when customer_id blank" do
    account.update!(stripe_customer_id: nil)

    assert_not account.has_stripe_customer?
  end

  test "has_active_subscription? requires both subscription_id and active status" do
    account.update!(stripe_subscription_id: "sub_123", billing_status: :active)

    assert_predicate account, :has_active_subscription?

    account.update!(billing_status: :past_due)

    assert_not account.has_active_subscription?

    account.update!(stripe_subscription_id: nil, billing_status: :active)

    assert_not account.has_active_subscription?
  end

  # --- Banner Display ---

  test "billing_banner_type returns :past_due for past_due accounts" do
    account.update!(billing_status: :past_due, payment_failed_at: 1.day.ago)

    assert_equal ::Billing::BANNER_PAST_DUE, account.billing_banner_type
  end

  test "billing_banner_type returns :free_until_expiring when expiring soon" do
    account.update!(billing_status: :free_until, free_until: 5.days.from_now)

    assert_equal ::Billing::BANNER_FREE_UNTIL_EXPIRING, account.billing_banner_type
  end

  test "billing_banner_type returns :usage_limit at 100%" do
    account.update!(billing_status: :free_forever, plan: free_plan)
    Rails.cache.write(account.usage_cache_key, Billing::FREE_EVENT_LIMIT)

    assert_equal ::Billing::BANNER_USAGE_LIMIT, account.billing_banner_type
  end

  test "billing_banner_type returns :usage_warning at 80%" do
    account.update!(billing_status: :free_forever, plan: free_plan)
    limit = Billing::FREE_EVENT_LIMIT
    Rails.cache.write(account.usage_cache_key, (limit * 0.8).to_i)

    assert_equal ::Billing::BANNER_USAGE_WARNING, account.billing_banner_type
  end

  test "billing_banner_type returns nil when no warnings" do
    account.update!(billing_status: :active, plan: starter_plan)
    Rails.cache.write(account.usage_cache_key, 1000)

    assert_nil account.billing_banner_type
  end

  test "free_until_expiring_soon? returns true within warning window" do
    account.update!(billing_status: :free_until, free_until: 5.days.from_now)

    assert_predicate account, :free_until_expiring_soon?
  end

  test "free_until_expiring_soon? returns false outside warning window" do
    account.update!(billing_status: :free_until, free_until: 14.days.from_now)

    assert_not account.free_until_expiring_soon?
  end

  test "days_until_free_expires calculates correctly" do
    account.update!(free_until: 5.days.from_now)

    assert_equal 5, account.days_until_free_expires
  end

  # --- Scopes ---

  test "billing_active scope includes correct statuses" do
    account.update!(billing_status: :active)
    other_account.update!(billing_status: :cancelled)

    active = Account.billing_active

    assert_includes active, account
    assert_not_includes active, other_account
  end

  test "past_due scope includes only past_due" do
    account.update!(billing_status: :past_due)
    other_account.update!(billing_status: :active)

    past_due = Account.past_due

    assert_includes past_due, account
    assert_not_includes past_due, other_account
  end

  test "with_expiring_free_until scope finds accounts expiring within days" do
    account.update!(billing_status: :free_until, free_until: 5.days.from_now)
    other_account.update!(billing_status: :free_until, free_until: 30.days.from_now)

    expiring = Account.with_expiring_free_until(7)

    assert_includes expiring, account
    assert_not_includes expiring, other_account
  end

  # --- Ad Platform Connection Limits ---

  test "can_connect_ad_platform? returns false for free plan" do
    account.update!(plan: free_plan)

    assert_not account.can_connect_ad_platform?
  end

  test "can_connect_ad_platform? returns false for nil plan" do
    account.update!(plan: nil)

    assert_not account.can_connect_ad_platform?
  end

  test "can_connect_ad_platform? returns true for starter with no connections" do
    account.update!(plan: starter_plan)
    account.ad_platform_connections.destroy_all

    assert_predicate account, :can_connect_ad_platform?
  end

  test "can_connect_ad_platform? returns false for starter at limit" do
    account.update!(plan: starter_plan)
    account.ad_platform_connections.where(status: [ :connected, :syncing ]).count
    # starter_plan allows 1 connection — account fixture already has google_ads (connected)

    assert_not account.can_connect_ad_platform?
  end

  test "can_connect_ad_platform? returns true for growth under limit" do
    account.update!(plan: growth_plan)
    # account has 2 connections (google_ads + google_ads_error), error status doesn't count

    assert_predicate account, :can_connect_ad_platform?
  end

  test "can_connect_ad_platform? returns true for pro regardless of count" do
    account.update!(plan: pro_plan)

    assert_predicate account, :can_connect_ad_platform?
  end

  test "can_connect_ad_platform? ignores disconnected and error connections" do
    account.update!(plan: starter_plan)
    # google_ads is connected (counts), google_ads_error is error (doesn't count)
    # Starter limit is 1, so 1 connected = at limit

    assert_not account.can_connect_ad_platform?
  end

  # --- Attribution Model Limits ---

  test "custom_model_limit returns 0 for free plan" do
    account.update!(plan: free_plan)

    assert_equal 0, account.custom_model_limit
  end

  test "custom_model_limit returns 3 for starter plan" do
    account.update!(plan: starter_plan)

    assert_equal 3, account.custom_model_limit
  end

  test "custom_model_limit returns 5 for growth plan" do
    account.update!(plan: growth_plan)

    assert_equal 5, account.custom_model_limit
  end

  test "custom_model_limit returns 10 for pro plan" do
    account.update!(plan: pro_plan)

    assert_equal 10, account.custom_model_limit
  end

  test "custom_model_limit defaults to 0 for nil plan" do
    account.update!(plan: nil)

    assert_equal 0, account.custom_model_limit
  end

  test "custom_models_count returns count of custom models" do
    account.attribution_models.create!(name: "Custom 1", model_type: :custom, dsl_code: "test")
    account.attribution_models.create!(name: "Custom 2", model_type: :custom, dsl_code: "test")
    account.attribution_models.create!(name: "Preset", model_type: :preset, algorithm: :first_touch)

    assert_equal 2, account.custom_models_count
  end

  test "can_create_custom_model? returns true when under limit" do
    account.update!(plan: starter_plan)
    account.attribution_models.create!(name: "Custom 1", model_type: :custom, dsl_code: "test")

    assert_predicate account, :can_create_custom_model?
  end

  test "can_create_custom_model? returns false when at limit" do
    account.update!(plan: starter_plan)
    3.times { |i| account.attribution_models.create!(name: "Custom #{i}", model_type: :custom, dsl_code: "test") }

    assert_not account.can_create_custom_model?
  end

  test "can_create_custom_model? returns false for free plan" do
    account.update!(plan: free_plan)

    assert_not account.can_create_custom_model?
  end

  test "can_edit_full_aml? returns false for free plan" do
    account.update!(plan: free_plan)

    assert_not account.can_edit_full_aml?
  end

  test "can_edit_full_aml? returns false for nil plan" do
    account.update!(plan: nil)

    assert_not account.can_edit_full_aml?
  end

  test "can_edit_full_aml? returns true for starter plan" do
    account.update!(plan: starter_plan)

    assert_predicate account, :can_edit_full_aml?
  end

  test "can_edit_full_aml? returns true for growth plan" do
    account.update!(plan: growth_plan)

    assert_predicate account, :can_edit_full_aml?
  end

  test "can_edit_full_aml? returns true for pro plan" do
    account.update!(plan: pro_plan)

    assert_predicate account, :can_edit_full_aml?
  end

  private

  def account
    @account ||= accounts(:one)
  end

  def other_account
    @other_account ||= accounts(:two)
  end

  def free_plan
    @free_plan ||= plans(:free)
  end

  def starter_plan
    @starter_plan ||= plans(:starter)
  end

  def growth_plan
    @growth_plan ||= plans(:growth)
  end

  def pro_plan
    @pro_plan ||= plans(:pro)
  end
end
