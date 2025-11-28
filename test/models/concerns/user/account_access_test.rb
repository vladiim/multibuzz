require "test_helper"

class User::AccountAccessTest < ActiveSupport::TestCase
  test "#member_of? returns true for accepted membership" do
    assert user_one.member_of?(account_one)
  end

  test "#member_of? returns false for pending membership" do
    assert_not user_two.member_of?(account_one)
  end

  test "#member_of? returns false for no membership" do
    assert_not user_one.member_of?(accounts(:suspended))
  end

  test "#owner_of? returns true for owner" do
    assert user_one.owner_of?(account_one)
  end

  test "#owner_of? returns false for non-owner" do
    assert_not user_one.owner_of?(account_two)
  end

  test "#admin_of? returns true for owner" do
    assert user_one.admin_of?(account_one)
  end

  test "#admin_of? returns true for admin" do
    create_membership(user: user_two, account: accounts(:suspended), role: :admin)
    assert user_two.admin_of?(accounts(:suspended))
  end

  test "#admin_of? returns false for member" do
    assert_not user_one.admin_of?(account_two)
  end

  test "#role_for returns role string" do
    assert_equal "owner", user_one.role_for(account_one)
    assert_equal "member", user_one.role_for(account_two)
  end

  test "#role_for returns nil for no membership" do
    assert_nil user_one.role_for(accounts(:suspended))
  end

  test "#active_accounts returns only accepted memberships" do
    active = user_one.active_accounts
    assert_includes active, account_one
    assert_includes active, account_two
  end

  test "#primary_account returns highest role account" do
    assert_equal account_one, user_one.primary_account
  end

  test "#membership_for excludes soft deleted" do
    # Create membership on suspended account, then soft delete (bypass validation)
    membership = create_membership(account: accounts(:suspended), role: :member)
    membership.update_column(:deleted_at, Time.current)

    assert_nil user_one.membership_for(accounts(:suspended))
  end

  private

  def create_membership(attrs = {})
    AccountMembership.create!(membership_defaults.merge(attrs))
  end

  def membership_defaults
    { user: user_one, account: accounts(:suspended), role: :member, status: :accepted }
  end

  def user_one
    @user_one ||= users(:one)
  end

  def user_two
    @user_two ||= users(:two)
  end

  def account_one
    @account_one ||= accounts(:one)
  end

  def account_two
    @account_two ||= accounts(:two)
  end
end
