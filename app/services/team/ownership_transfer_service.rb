# frozen_string_literal: true

module Team
  class OwnershipTransferService < ApplicationService
    VALIDATIONS = {
      missing_confirmation?: [ :validation, "Confirmation is required" ],
      wrong_confirmation?: [ :validation, "Confirmation does not match account name" ],
      not_owner?: [ :forbidden, "Only the owner can transfer ownership" ],
      new_owner_missing?: [ :validation, "New owner not found" ],
      transfer_to_self?: [ :validation, "Cannot transfer ownership to yourself" ],
      new_owner_pending?: [ :validation, "Cannot transfer to a pending membership" ]
    }.freeze

    def initialize(actor:, account:, new_owner_membership:, confirmation:)
      @actor = actor
      @account = account
      @new_owner_membership = new_owner_membership
      @confirmation = confirmation&.strip
    end

    private

    attr_reader :actor, :account, :new_owner_membership, :confirmation

    def run
      validation_error || perform_transfer
    end

    def validation_error
      VALIDATIONS.each { |check, (code, message)| return error_with_code(code, message) if send(check) }
      nil
    end

    def error_with_code(code, message)
      { success: false, error_code: code, errors: [ message ] }
    end

    def missing_confirmation?
      confirmation.blank?
    end

    def wrong_confirmation?
      confirmation != account.name
    end

    def not_owner?
      !actor_membership&.owner?
    end

    def new_owner_missing?
      new_owner_membership.blank? || new_owner_membership.account_id != account.id || new_owner_membership.deleted_at.present?
    end

    def transfer_to_self?
      actor.id == new_owner_membership.user_id
    end

    def new_owner_pending?
      !new_owner_membership.accepted?
    end

    def perform_transfer
      ActiveRecord::Base.transaction do
        actor_membership.update!(role: :admin)
        new_owner_membership.update!(role: :owner)
      end
      notify_new_owner
      notify_previous_owner
      success_result
    end

    def notify_new_owner
      TeamMailer.ownership_transferred_to_new_owner(
        account: account,
        new_owner: new_owner_membership.user,
        previous_owner: actor
      ).deliver_later
    end

    def notify_previous_owner
      TeamMailer.ownership_transferred_to_previous_owner(
        account: account,
        new_owner: new_owner_membership.user,
        previous_owner: actor
      ).deliver_later
    end

    def actor_membership
      @actor_membership ||= actor.membership_for(account)
    end
  end
end
