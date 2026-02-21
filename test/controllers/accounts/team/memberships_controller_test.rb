# frozen_string_literal: true

require "test_helper"

module Accounts
  module Team
    class MembershipsControllerTest < ActionDispatch::IntegrationTest
      # ==========================================
      # Update action - Role changes
      # ==========================================

      test "owner can change member to admin" do
        sign_in_as owner

        patch account_team_membership_path(member_membership), params: { role: "admin" }

        assert_redirected_to account_team_path
        assert_predicate member_membership.reload, :admin?
      end

      test "owner can change admin to member" do
        sign_in_as owner

        patch account_team_membership_path(admin_membership), params: { role: "member" }

        assert_redirected_to account_team_path
        assert_predicate admin_membership.reload, :member?
      end

      test "admin can change member to admin" do
        sign_in_as admin_user

        patch account_team_membership_path(member_membership), params: { role: "admin" }

        assert_redirected_to account_team_path
        assert_predicate member_membership.reload, :admin?
      end

      test "admin cannot demote other admin" do
        sign_in_as admin_user

        patch account_team_membership_path(other_admin_membership), params: { role: "member" }

        assert_response :forbidden
        assert_predicate other_admin_membership.reload, :admin?
      end

      test "admin cannot promote to owner" do
        sign_in_as admin_user

        patch account_team_membership_path(member_membership), params: { role: "owner" }

        assert_response :forbidden
        assert_predicate member_membership.reload, :member?
      end

      test "owner cannot change own role" do
        sign_in_as owner

        patch account_team_membership_path(owner_membership), params: { role: "admin" }

        assert_response :unprocessable_entity
        assert_predicate owner_membership.reload, :owner?
      end

      test "member cannot change roles" do
        sign_in_as member_user

        patch account_team_membership_path(admin_membership), params: { role: "member" }

        assert_response :forbidden
      end

      test "cannot change role of pending membership" do
        sign_in_as owner

        patch account_team_membership_path(pending_membership), params: { role: "admin" }

        assert_response :unprocessable_entity
      end

      # ==========================================
      # Destroy action - Member removal
      # ==========================================

      test "owner can remove member" do
        sign_in_as owner

        delete account_team_membership_path(member_membership)

        assert_redirected_to account_team_path
        assert_predicate member_membership.reload.deleted_at, :present?
      end

      test "owner can remove admin" do
        sign_in_as owner

        delete account_team_membership_path(admin_membership)

        assert_redirected_to account_team_path
        assert_predicate admin_membership.reload.deleted_at, :present?
      end

      test "admin can remove member" do
        sign_in_as admin_user

        delete account_team_membership_path(member_membership)

        assert_redirected_to account_team_path
        assert_predicate member_membership.reload.deleted_at, :present?
      end

      test "admin cannot remove other admin" do
        sign_in_as admin_user

        delete account_team_membership_path(other_admin_membership)

        assert_response :forbidden
        assert_nil other_admin_membership.reload.deleted_at
      end

      test "admin cannot remove owner" do
        sign_in_as admin_user

        delete account_team_membership_path(owner_membership)

        assert_response :forbidden
        assert_nil owner_membership.reload.deleted_at
      end

      test "owner cannot remove self" do
        sign_in_as owner

        delete account_team_membership_path(owner_membership)

        assert_response :unprocessable_entity
        assert_nil owner_membership.reload.deleted_at
      end

      test "member cannot remove anyone" do
        sign_in_as member_user

        delete account_team_membership_path(admin_membership)

        assert_response :forbidden
      end

      test "soft deletes membership preserving audit trail" do
        sign_in_as owner

        delete account_team_membership_path(member_membership)

        member_membership.reload

        assert_predicate member_membership.deleted_at, :present?
        assert_equal "accepted", member_membership.status
      end

      private

      def sign_in_as(user)
        post login_path, params: { email: user.email, password: "password123" }
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
end
