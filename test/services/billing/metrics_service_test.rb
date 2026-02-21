# frozen_string_literal: true

require "test_helper"

class Billing::MetricsServiceTest < ActiveSupport::TestCase
  test "calculates total MRR from active subscriptions" do
    setup_active_account(starter_plan)
    setup_active_account(growth_plan)

    assert_equal 12800, result[:mrr_cents]
    assert_in_delta(128.00, result[:mrr])
  end

  test "excludes non-active accounts from MRR" do
    setup_active_account(starter_plan)
    setup_account_with_status(:trialing, growth_plan)
    setup_account_with_status(:free_forever, nil)
    setup_account_with_status(:cancelled, starter_plan)

    assert_equal 2900, result[:mrr_cents]
  end

  test "includes past_due accounts in MRR" do
    setup_active_account(starter_plan)
    setup_account_with_status(:past_due, growth_plan)

    assert_equal 12800, result[:mrr_cents]
  end

  test "returns account counts by status" do
    baseline_free_forever = Account.where(billing_status: :free_forever).count

    setup_active_account(starter_plan)
    setup_account_with_status(:trialing, growth_plan)
    setup_account_with_status(:free_forever, nil)
    setup_account_with_status(:free_until, starter_plan)
    setup_account_with_status(:cancelled, starter_plan)

    counts = result[:account_counts]

    assert_equal 1, counts[:active]
    assert_equal 1, counts[:trialing]
    assert_equal baseline_free_forever + 1, counts[:free_forever]
    assert_equal 1, counts[:free_until]
    assert_equal 1, counts[:cancelled]
  end

  test "returns MRR breakdown by plan" do
    setup_active_account(starter_plan)
    setup_active_account(starter_plan)
    setup_active_account(growth_plan)

    breakdown = result[:mrr_by_plan]

    assert_equal 5800, breakdown[starter_plan.id]
    assert_equal 9900, breakdown[growth_plan.id]
  end

  test "returns total account count" do
    baseline = Account.count

    setup_active_account(starter_plan)
    setup_account_with_status(:trialing, growth_plan)

    assert_equal baseline + 2, result[:total_accounts]
  end

  private

  def result
    @result ||= service.call
  end

  def service
    Billing::MetricsService.new
  end

  def starter_plan
    @starter_plan ||= plans(:starter)
  end

  def growth_plan
    @growth_plan ||= plans(:growth)
  end

  def setup_active_account(plan)
    setup_account_with_status(:active, plan)
  end

  def setup_account_with_status(status, plan)
    Account.create!(
      name: "Test Account #{SecureRandom.hex(4)}",
      slug: "test-#{SecureRandom.hex(8)}",
      billing_status: status,
      plan: plan
    )
  end
end
