# frozen_string_literal: true

require "test_helper"

module Accounts
  module Team
    class OwnershipControllerTest < ActionDispatch::IntegrationTest
      # ==========================================
      # Transfer action - Ownership transfer
      # ==========================================

      test "owner can transfer ownership to admin" do
        sign_in_as owner

        post transfer_account_team_ownership_path, params: {
          new_owner_id: admin_membership.prefix_id,
          confirmation: account.name
        }

        assert_redirected_to account_team_path
        admin_membership.reload
        owner_membership.reload

        assert_predicate admin_membership, :owner?
        assert_predicate owner_membership, :admin?
      end

      test "owner can transfer ownership to member" do
        sign_in_as owner

        post transfer_account_team_ownership_path, params: {
          new_owner_id: member_membership.prefix_id,
          confirmation: account.name
        }

        assert_redirected_to account_team_path
        member_membership.reload
        owner_membership.reload

        assert_predicate member_membership, :owner?
        assert_predicate owner_membership, :admin?
      end

      test "transfer requires correct confirmation" do
        sign_in_as owner

        post transfer_account_team_ownership_path, params: {
          new_owner_id: admin_membership.prefix_id,
          confirmation: "wrong name"
        }

        assert_response :unprocessable_entity
        admin_membership.reload

        assert_predicate admin_membership, :admin?
      end

      test "transfer requires confirmation" do
        sign_in_as owner

        post transfer_account_team_ownership_path, params: {
          new_owner_id: admin_membership.prefix_id
        }

        assert_response :unprocessable_entity
      end

      test "admin cannot transfer ownership" do
        sign_in_as admin_user

        post transfer_account_team_ownership_path, params: {
          new_owner_id: member_membership.prefix_id,
          confirmation: account.name
        }

        assert_response :forbidden
      end

      test "member cannot transfer ownership" do
        sign_in_as member_user

        post transfer_account_team_ownership_path, params: {
          new_owner_id: admin_membership.prefix_id,
          confirmation: account.name
        }

        assert_response :forbidden
      end

      test "cannot transfer to pending membership" do
        sign_in_as owner

        post transfer_account_team_ownership_path, params: {
          new_owner_id: pending_membership.prefix_id,
          confirmation: account.name
        }

        assert_response :unprocessable_entity
      end

      test "cannot transfer to self" do
        sign_in_as owner

        post transfer_account_team_ownership_path, params: {
          new_owner_id: owner_membership.prefix_id,
          confirmation: account.name
        }

        assert_response :unprocessable_entity
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

      def member_user
        @member_user ||= users(:four)
      end

      def member_membership
        @member_membership ||= account_memberships(:member_in_one)
      end

      def pending_membership
        @pending_membership ||= account_memberships(:pending_invite)
      end
    end
  end
end
