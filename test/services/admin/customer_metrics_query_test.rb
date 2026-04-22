# frozen_string_literal: true

require "test_helper"

class Admin::CustomerMetricsQueryTest < ActiveSupport::TestCase
  test "returns one row per account" do
    expected = Account.count

    assert_equal expected, query.call.size
  end

  test "row exposes the account name and prefix_id" do
    row = row_for(account)

    assert_equal account.name, row.name
    assert_equal account.prefix_id, row.prefix_id
  end

  test "row reflects the persisted billing_status and plan name" do
    account.update!(plan: starter_plan, billing_status: :active)

    row = row_for(account)

    assert_equal "active", row.billing_status
    assert_equal starter_plan.name, row.plan_name
  end

  test "row exposes lifetime_value_cents from the denormalised counter" do
    account.update!(lifetime_value_cents: 12_345)

    assert_equal 12_345, row_for(account).lifetime_value_cents
  end

  test "row reports churn date as subscription_cancelled_at" do
    cancelled_on = 3.days.ago
    account.update!(subscription_cancelled_at: cancelled_on)

    assert_in_delta cancelled_on.to_i, row_for(account).churn_date.to_i, 1
  end

  test "row counts only the account's own production events" do
    other = accounts(:two)
    Event.where(account_id: [ account.id, other.id ]).delete_all
    create_event(account, is_test: false)
    create_event(account, is_test: false)
    create_event(other, is_test: false)
    create_event(account, is_test: true)

    assert_equal 2, row_for(account).total_prod_records
  end

  test "row reports has_test_records true when any test event exists" do
    create_event(account, is_test: true)

    assert row_for(account).has_test_records
  end

  test "row reports has_test_records false when only production events exist" do
    create_event(account, is_test: false)

    refute row_for(account).has_test_records
  end

  test "row aggregates user_count from accepted memberships" do
    expected = account.account_memberships.accepted.count

    assert_equal expected, row_for(account).user_count
  end

  test "row sums sign_in_count across accepted memberships" do
    users(:one).update!(sign_in_count: 4)
    users(:three).update!(sign_in_count: 1) # admin_in_one
    users(:four).update!(sign_in_count: 2) # member_in_one

    assert_equal 7, row_for(account).user_login_count
  end

  test "row reports the most recent last_sign_in_at across accepted memberships" do
    most_recent = 1.hour.ago
    users(:one).update!(last_sign_in_at: 1.day.ago)
    users(:three).update!(last_sign_in_at: most_recent)
    users(:four).update!(last_sign_in_at: 2.days.ago)

    assert_in_delta most_recent.to_i, row_for(account).last_login_at.to_i, 1
  end

  test "row reports days_to_activation when activated_at is set" do
    account.update!(created_at: 10.days.ago, activated_at: 7.days.ago)

    assert_equal 3, row_for(account).days_to_activation
  end

  test "row reports days_to_activation as nil when not activated" do
    account.update!(activated_at: nil)

    assert_nil row_for(account).days_to_activation
  end

  test "row reports onboarding_percentage from the existing helper" do
    assert_equal account.onboarding_percentage, row_for(account).onboarding_percentage
  end

  test "row reports active_subscription_months from subscription_started_at" do
    account.update!(subscription_started_at: 90.days.ago, subscription_cancelled_at: nil)

    assert_in_delta 3, row_for(account).active_subscription_months, 1
  end

  test "row counts ad platform connections" do
    expected = account.ad_platform_connections.count

    assert_equal expected, row_for(account).connected_integrations
  end

  test "default order is newest signups first" do
    rows = query.call

    creation_dates = rows.map { |r| r.signed_up_at.to_i }

    assert_equal creation_dates.sort.reverse, creation_dates
  end

  private

  def query = @query ||= Admin::CustomerMetricsQuery.new
  def account = @account ||= accounts(:one)
  def starter_plan = @starter_plan ||= plans(:starter)

  def row_for(account)
    Admin::CustomerMetricsQuery.new.call.find { |r| r.id == account.id }
  end

  def create_event(account, is_test:)
    account.events.create!(
      event_type: "page_view",
      visitor: visitors(:one),
      session: sessions(:one),
      occurred_at: 1.hour.ago,
      properties: { url: "https://example.com" },
      is_test: is_test
    )
  end
end
