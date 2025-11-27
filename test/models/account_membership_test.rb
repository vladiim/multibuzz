require "test_helper"

class AccountMembershipTest < ActiveSupport::TestCase
  test "valid membership" do
    assert build_membership.valid?
  end

  test "requires role" do
    membership = build_membership(role: nil)
    assert_not membership.valid?
    assert_includes membership.errors[:role], "can't be blank"
  end

  test "requires status" do
    membership = build_membership(status: nil)
    assert_not membership.valid?
    assert_includes membership.errors[:status], "can't be blank"
  end

  test "active scope returns accepted non-deleted memberships" do
    active = AccountMembership.active
    assert active.all? { |m| m.accepted? && m.deleted_at.nil? }
  end

  test "prevents revoking last owner" do
    owner_one_membership.status = :revoked

    assert_not owner_one_membership.valid?
    assert_includes owner_one_membership.errors[:base], "account must have at least one owner"
  end

  test "prevents soft deleting last owner" do
    owner_one_membership.deleted_at = Time.current

    assert_not owner_one_membership.valid?
    assert_includes owner_one_membership.errors[:base], "account must have at least one owner"
  end

  test "allows revoking owner if another owner exists" do
    # Create fresh owner on suspended_account (no existing memberships)
    first_owner = create_membership(account: suspended_account, role: :owner)
    create_membership(user: user_two, account: suspended_account, role: :owner)

    first_owner.status = :revoked
    assert first_owner.valid?
  end

  test "role enum values" do
    assert_equal 0, AccountMembership.roles[:viewer]
    assert_equal 1, AccountMembership.roles[:member]
    assert_equal 2, AccountMembership.roles[:admin]
    assert_equal 3, AccountMembership.roles[:owner]
  end

  test "status enum values" do
    assert_equal 0, AccountMembership.statuses[:pending]
    assert_equal 1, AccountMembership.statuses[:accepted]
    assert_equal 2, AccountMembership.statuses[:declined]
    assert_equal 3, AccountMembership.statuses[:revoked]
  end

  test "has prefix_id" do
    assert owner_one_membership.prefix_id.start_with?("mem_")
  end

  private

  def build_membership(attrs = {})
    AccountMembership.new(membership_defaults.merge(attrs))
  end

  def create_membership(attrs = {})
    AccountMembership.create!(membership_defaults.merge(attrs))
  end

  def membership_defaults
    { user: user_one, account: suspended_account, role: :member, status: :accepted }
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

  def suspended_account
    @suspended_account ||= accounts(:suspended)
  end

  def owner_one_membership
    @owner_one_membership ||= account_memberships(:owner_one)
  end
end
