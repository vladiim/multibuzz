# frozen_string_literal: true

require "test_helper"

module Team
  class RoleChangeServiceTest < ActiveSupport::TestCase
    # ==========================================
    # Owner changing roles
    # ==========================================

    test "owner can promote member to admin" do
      assert promote_member_to_admin[:success]
      assert_predicate member_membership.reload, :admin?
    end

    test "owner can demote admin to member" do
      assert demote_admin_to_member[:success]
      assert_predicate admin_membership.reload, :member?
    end

    test "owner cannot change own role" do
      assert_not owner_self_demote[:success]
      assert_includes owner_self_demote[:errors], "Cannot change your own role"
      assert_predicate owner_membership.reload, :owner?
    end

    # ==========================================
    # Admin changing roles
    # ==========================================

    test "admin can promote member to admin" do
      assert admin_promotes_member[:success]
      assert_predicate member_membership.reload, :admin?
    end

    test "admin cannot demote other admin" do
      assert_not admin_demotes_admin[:success]
      assert_includes admin_demotes_admin[:errors], "Cannot change the role of another admin"
      assert_predicate other_admin_membership.reload, :admin?
    end

    test "admin cannot promote to owner" do
      assert_not admin_promotes_to_owner[:success]
      assert_includes admin_promotes_to_owner[:errors], "Only owners can assign owner role"
      assert_predicate member_membership.reload, :member?
    end

    test "admin cannot change owner role" do
      assert_not admin_changes_owner[:success]
      assert_predicate owner_membership.reload, :owner?
    end

    # ==========================================
    # Member attempting changes (forbidden)
    # ==========================================

    test "member cannot change roles" do
      assert_not member_changes_role[:success]
      assert_includes member_changes_role[:errors], "Not authorized to change roles"
    end

    # ==========================================
    # Edge cases
    # ==========================================

    test "cannot change role of pending membership" do
      assert_not change_pending_role[:success]
      assert_includes change_pending_role[:errors], "Cannot change role of pending membership"
    end

    test "cannot change role to invalid value" do
      assert_not invalid_role_change[:success]
      assert_includes invalid_role_change[:errors], "Invalid role"
    end

    test "no-op when role unchanged" do
      assert same_role_change[:success]
      assert_predicate member_membership.reload, :member?
    end

    test "cannot change role of deleted membership" do
      member_membership.update!(deleted_at: Time.current)

      assert_not deleted_membership_change[:success]
      assert_includes deleted_membership_change[:errors], "Membership not found"
    end

    private

    def promote_member_to_admin
      @promote_member_to_admin ||= build_service(actor: owner, membership: member_membership, new_role: "admin").call
    end

    def demote_admin_to_member
      @demote_admin_to_member ||= build_service(actor: owner, membership: admin_membership, new_role: "member").call
    end

    def owner_self_demote
      @owner_self_demote ||= build_service(actor: owner, membership: owner_membership, new_role: "admin").call
    end

    def admin_promotes_member
      @admin_promotes_member ||= build_service(actor: admin_user, membership: member_membership, new_role: "admin").call
    end

    def admin_demotes_admin
      @admin_demotes_admin ||= build_service(actor: admin_user, membership: other_admin_membership, new_role: "member").call
    end

    def admin_promotes_to_owner
      @admin_promotes_to_owner ||= build_service(actor: admin_user, membership: member_membership, new_role: "owner").call
    end

    def admin_changes_owner
      @admin_changes_owner ||= build_service(actor: admin_user, membership: owner_membership, new_role: "admin").call
    end

    def member_changes_role
      @member_changes_role ||= build_service(actor: member_user, membership: admin_membership, new_role: "member").call
    end

    def change_pending_role
      @change_pending_role ||= build_service(actor: owner, membership: pending_membership, new_role: "admin").call
    end

    def invalid_role_change
      @invalid_role_change ||= build_service(actor: owner, membership: member_membership, new_role: "superuser").call
    end

    def same_role_change
      @same_role_change ||= build_service(actor: owner, membership: member_membership, new_role: "member").call
    end

    def deleted_membership_change
      @deleted_membership_change ||= build_service(actor: owner, membership: member_membership, new_role: "admin").call
    end

    def build_service(actor:, membership:, new_role:)
      RoleChangeService.new(actor: actor, membership: membership, new_role: new_role)
    end

    def account
      @account ||= accounts(:one)
    end

    def owner
      @owner ||= users(:one)
    end

    def owner_membership
      @owner_membership ||= account_memberships(:owner_one)
    end

    def admin_user
      @admin_user ||= users(:three)
    end

    def admin_membership
      @admin_membership ||= account_memberships(:admin_in_one)
    end

    def other_admin_membership
      @other_admin_membership ||= create_other_admin
    end

    def member_user
      @member_user ||= users(:four)
    end

    def member_membership
      @member_membership ||= account_memberships(:member_in_one)
    end

    def pending_membership
      @pending_membership ||= account_memberships(:pending_invite)
    end

    def create_other_admin
      user = User.create!(email: "other_admin@example.com", password: "password123")
      AccountMembership.create!(
        user: user,
        account: account,
        role: :admin,
        status: :accepted,
        accepted_at: Time.current
      )
    end
  end
end
