# frozen_string_literal: true

require "test_helper"

module Team
  class RemovalServiceTest < ActiveSupport::TestCase
    # ==========================================
    # Owner removing members
    # ==========================================

    test "owner can remove member" do
      assert owner_removes_member[:success]
      assert_predicate member_membership.reload.deleted_at, :present?
    end

    test "owner can remove admin" do
      assert owner_removes_admin[:success]
      assert_predicate admin_membership.reload.deleted_at, :present?
    end

    test "owner cannot remove self" do
      assert_not owner_removes_self[:success]
      assert_includes owner_removes_self[:errors], "Cannot remove yourself"
      assert_nil owner_membership.reload.deleted_at
    end

    # ==========================================
    # Admin removing members
    # ==========================================

    test "admin can remove member" do
      assert admin_removes_member[:success]
      assert_predicate member_membership.reload.deleted_at, :present?
    end

    test "admin cannot remove other admin" do
      assert_not admin_removes_admin[:success]
      assert_includes admin_removes_admin[:errors], "Cannot remove another admin"
      assert_nil other_admin_membership.reload.deleted_at
    end

    test "admin cannot remove owner" do
      assert_not admin_removes_owner[:success]
      assert_includes admin_removes_owner[:errors], "Cannot remove the owner"
      assert_nil owner_membership.reload.deleted_at
    end

    # ==========================================
    # Member attempting removal (forbidden)
    # ==========================================

    test "member cannot remove anyone" do
      assert_not member_removes_admin[:success]
      assert_includes member_removes_admin[:errors], "Not authorized to remove members"
    end

    # ==========================================
    # Soft delete behavior
    # ==========================================

    test "soft deletes membership preserving status" do
      assert owner_removes_member[:success]

      member_membership.reload

      assert_predicate member_membership.deleted_at, :present?
      assert_predicate member_membership, :accepted?
    end

    test "cannot remove already deleted membership" do
      member_membership.update!(deleted_at: Time.current)

      assert_not remove_deleted_membership[:success]
      assert_includes remove_deleted_membership[:errors], "Membership not found"
    end

    test "cannot remove pending invitation via removal service" do
      assert_not remove_pending[:success]
      assert_includes remove_pending[:errors], "Use invitation cancellation for pending invites"
    end

    private

    def owner_removes_member
      @owner_removes_member ||= build_service(actor: owner, membership: member_membership).call
    end

    def owner_removes_admin
      @owner_removes_admin ||= build_service(actor: owner, membership: admin_membership).call
    end

    def owner_removes_self
      @owner_removes_self ||= build_service(actor: owner, membership: owner_membership).call
    end

    def admin_removes_member
      @admin_removes_member ||= build_service(actor: admin_user, membership: member_membership).call
    end

    def admin_removes_admin
      @admin_removes_admin ||= build_service(actor: admin_user, membership: other_admin_membership).call
    end

    def admin_removes_owner
      @admin_removes_owner ||= build_service(actor: admin_user, membership: owner_membership).call
    end

    def member_removes_admin
      @member_removes_admin ||= build_service(actor: member_user, membership: admin_membership).call
    end

    def remove_deleted_membership
      @remove_deleted_membership ||= build_service(actor: owner, membership: member_membership).call
    end

    def remove_pending
      @remove_pending ||= build_service(actor: owner, membership: pending_membership).call
    end

    def build_service(actor:, membership:)
      RemovalService.new(actor: actor, membership: membership)
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
