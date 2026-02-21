# frozen_string_literal: true

require "test_helper"

class Billing::ReportUsageServiceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "reports usage for accounts with active subscriptions" do
    account.update!(
      billing_status: :active,
      stripe_customer_id: "cus_123",
      stripe_subscription_id: "sub_123",
      plan: starter_plan
    )
    Rails.cache.write(account.usage_cache_key, 5000)

    result = service.call

    assert result[:success]
    assert_equal 5000, result[:usage_reported]
  end

  test "skips accounts without stripe subscription" do
    account.update!(
      billing_status: :free_forever,
      stripe_subscription_id: nil,
      plan: free_plan
    )

    result = service.call

    assert result[:skipped]
    assert_equal "No active subscription", result[:reason]
  end

  test "skips accounts with zero usage" do
    account.update!(
      billing_status: :active,
      stripe_customer_id: "cus_123",
      stripe_subscription_id: "sub_123",
      plan: starter_plan
    )

    result = service.call

    assert result[:skipped]
    assert_equal "No usage to report", result[:reason]
  end

  test "calculates overage correctly" do
    account.update!(
      billing_status: :active,
      stripe_customer_id: "cus_123",
      stripe_subscription_id: "sub_123",
      plan: starter_plan
    )
    starter_limit = Billing::STARTER_EVENT_LIMIT
    overage_amount = 250_000
    Rails.cache.write(account.usage_cache_key, starter_limit + overage_amount)

    result = service.call

    assert result[:success]
    assert_equal starter_limit + overage_amount, result[:usage_reported]
    assert_equal overage_amount, result[:overage_events]
  end

  test "no overage when under plan limit" do
    account.update!(
      billing_status: :active,
      stripe_customer_id: "cus_123",
      stripe_subscription_id: "sub_123",
      plan: starter_plan
    )
    Rails.cache.write(account.usage_cache_key, (Billing::STARTER_EVENT_LIMIT * 0.3).to_i)

    result = service.call

    assert result[:success]
    assert_equal 0, result[:overage_events]
  end

  private

  def service
    @service ||= Billing::ReportUsageService.new(account)
  end

  def account
    @account ||= accounts(:one)
  end

  def free_plan
    @free_plan ||= plans(:free)
  end

  def starter_plan
    @starter_plan ||= plans(:starter)
  end
end
