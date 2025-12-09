require "test_helper"

module Team
  class OwnershipTransferServiceTest < ActiveSupport::TestCase
    include ActionMailer::TestHelper
    # ==========================================
    # Successful transfers
    # ==========================================

    test "transfers ownership to admin" do
      assert transfer_to_admin[:success]
      assert admin_membership.reload.owner?
      assert owner_membership.reload.admin?
    end

    test "transfers ownership to member" do
      assert transfer_to_member[:success]
      assert member_membership.reload.owner?
      assert owner_membership.reload.admin?
    end

    test "sends notification emails to both parties" do
      assert_enqueued_emails 2 do
        transfer_with_emails
      end
    end

    # ==========================================
    # Validation failures
    # ==========================================

    test "requires correct confirmation" do
      assert_not wrong_confirmation[:success]
      assert_includes wrong_confirmation[:errors], "Confirmation does not match account name"
    end

    test "requires confirmation" do
      assert_not missing_confirmation[:success]
      assert_includes missing_confirmation[:errors], "Confirmation is required"
    end

    test "only owner can transfer" do
      assert_not admin_attempts_transfer[:success]
      assert_includes admin_attempts_transfer[:errors], "Only the owner can transfer ownership"
    end

    test "cannot transfer to self" do
      assert_not transfer_to_self[:success]
      assert_includes transfer_to_self[:errors], "Cannot transfer ownership to yourself"
    end

    test "cannot transfer to pending membership" do
      assert_not transfer_to_pending[:success]
      assert_includes transfer_to_pending[:errors], "Cannot transfer to a pending membership"
    end

    test "cannot transfer to deleted membership" do
      member_membership.update!(deleted_at: Time.current)

      assert_not transfer_to_deleted[:success]
      assert_includes transfer_to_deleted[:errors], "New owner not found"
    end

    test "cannot transfer to membership from different account" do
      assert_not transfer_to_other_account[:success]
      assert_includes transfer_to_other_account[:errors], "New owner not found"
    end

    private

    def transfer_to_admin
      @transfer_to_admin ||= build_service(new_owner: admin_membership, confirmation: account.name).call
    end

    def transfer_to_member
      @transfer_to_member ||= build_service(new_owner: member_membership, confirmation: account.name).call
    end

    def transfer_with_emails
      build_service(new_owner: fresh_admin_membership, confirmation: account.name).call
    end

    def fresh_admin_membership
      account.account_memberships.find_by(user: admin_user)
    end

    def wrong_confirmation
      @wrong_confirmation ||= build_service(new_owner: admin_membership, confirmation: "wrong").call
    end

    def missing_confirmation
      @missing_confirmation ||= build_service(new_owner: admin_membership, confirmation: nil).call
    end

    def admin_attempts_transfer
      @admin_attempts_transfer ||= build_service(actor: admin_user, new_owner: member_membership, confirmation: account.name).call
    end

    def transfer_to_self
      @transfer_to_self ||= build_service(new_owner: owner_membership, confirmation: account.name).call
    end

    def transfer_to_pending
      @transfer_to_pending ||= build_service(new_owner: pending_membership, confirmation: account.name).call
    end

    def transfer_to_deleted
      @transfer_to_deleted ||= build_service(new_owner: member_membership, confirmation: account.name).call
    end

    def transfer_to_other_account
      @transfer_to_other_account ||= build_service(new_owner: other_account_membership, confirmation: account.name).call
    end

    def build_service(actor: owner, new_owner:, confirmation:)
      OwnershipTransferService.new(
        actor: actor,
        account: account,
        new_owner_membership: new_owner,
        confirmation: confirmation
      )
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

    def member_membership
      @member_membership ||= account_memberships(:member_in_one)
    end

    def pending_membership
      @pending_membership ||= account_memberships(:pending_invite)
    end

    def other_account_membership
      @other_account_membership ||= account_memberships(:owner_two)
    end
  end
end
