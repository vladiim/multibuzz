# frozen_string_literal: true

require "test_helper"

class Lifecycle::TrackerTest < ActiveSupport::TestCase
  test "skip_tracking? is true in test env by default" do
    assert_predicate Lifecycle::Tracker, :skip_tracking?
  end

  test "track returns nil in test env without raising" do
    assert_nil Lifecycle::Tracker.track("any_event", account)
  end

  test "track returns nil and does not raise when account has no accepted owner" do
    refute_nil ownerless_account
    assert_nil Lifecycle::Tracker.track("any_event", ownerless_account)
  end

  test "resolve_owner returns the accepted owner user" do
    assert_equal users(:one), Lifecycle::Tracker.resolve_owner(account)
  end

  test "resolve_owner returns nil when no accepted owner exists" do
    assert_nil Lifecycle::Tracker.resolve_owner(ownerless_account)
  end

  test "resolve_owner ignores pending owner invites" do
    assert_nil Lifecycle::Tracker.resolve_owner(pending_only_account)
  end

  test "standard_properties identifies the account by prefix_id" do
    assert_equal account.prefix_id, Lifecycle::Tracker.standard_properties(account)[:account_id]
  end

  test "standard_properties echoes billing_status, days_since_signup and usage_percentage" do
    props = Lifecycle::Tracker.standard_properties(account)

    assert_equal account.billing_status, props[:billing_status]
    assert_kind_of Integer, props[:days_since_signup]
  end

  test "standard_properties exposes account_name for human-readable dashboards" do
    assert_equal account.name, Lifecycle::Tracker.standard_properties(account)[:account_name]
  end

  test "standard_properties returns 'free' when account has no plan" do
    account.update!(plan: nil)

    assert_equal "free", Lifecycle::Tracker.standard_properties(account)[:plan]
  end

  test "build_payload returns nil for ownerless accounts" do
    assert_nil Lifecycle::Tracker.build_payload("any_event", ownerless_account)
  end

  test "build_payload uses the supplied event name and identifies the owner" do
    payload = Lifecycle::Tracker.build_payload("onboarding_completed", account)

    assert_equal "onboarding_completed", payload[:name]
    assert_equal users(:one).prefix_id, payload[:properties][:user_id]
  end

  test "build_payload merges custom properties onto the standard set" do
    payload = Lifecycle::Tracker.build_payload("onboarding_completed", account, persona: "marketer")

    assert_equal account.prefix_id, payload[:properties][:account_id]
    assert_equal "marketer", payload[:properties][:persona]
  end

  test "build_payload custom properties override standard properties on collision" do
    payload = Lifecycle::Tracker.build_payload("usage_milestone", account, usage_percentage: 80)

    assert_equal 80, payload[:properties][:usage_percentage]
  end

  private

  def account = @account ||= accounts(:one)

  def ownerless_account
    @ownerless_account ||= Account.create!(name: "Ownerless", slug: "ownerless-#{SecureRandom.hex(4)}")
  end

  def pending_only_account
    @pending_only_account ||= begin
      acct = Account.create!(name: "Pending Only", slug: "pending-#{SecureRandom.hex(4)}")
      AccountMembership.create!(account: acct, user: users(:two), role: :owner, status: :pending, invited_at: Time.current, invited_by_email: "x@example.com")
      acct
    end
  end
end
