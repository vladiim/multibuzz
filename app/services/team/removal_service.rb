# frozen_string_literal: true

module Team
  class RemovalService < ApplicationService
    VALIDATIONS = {
      membership_missing?: [ :not_found, "Membership not found" ],
      pending_membership?: [ :validation, "Use invitation cancellation for pending invites" ],
      unauthorized?: [ :forbidden, "Not authorized to remove members" ],
      self_removal?: [ :validation, "Cannot remove yourself" ],
      removing_owner?: [ :forbidden, "Cannot remove the owner" ],
      admin_removing_admin?: [ :forbidden, "Cannot remove another admin" ]
    }.freeze

    def initialize(actor:, membership:)
      @actor = actor
      @membership = membership
    end

    private

    attr_reader :actor, :membership

    def run
      validation_error || soft_delete
    end

    def validation_error
      VALIDATIONS.each { |check, (code, message)| return error_with_code(code, message) if send(check) }
      nil
    end

    def error_with_code(code, message)
      { success: false, error_code: code, errors: [ message ] }
    end

    def membership_missing?
      membership.blank? || membership.deleted_at.present?
    end

    def pending_membership?
      membership.pending?
    end

    def unauthorized?
      !actor_membership&.admin? && !actor_membership&.owner?
    end

    def self_removal?
      actor.id == membership.user_id
    end

    def removing_owner?
      membership.owner?
    end

    def admin_removing_admin?
      actor_admin_not_owner? && membership.admin?
    end

    def actor_admin_not_owner?
      actor_membership&.admin? && !actor_membership&.owner?
    end

    def soft_delete
      membership.update!(deleted_at: Time.current)
      success_result
    end

    def actor_membership
      @actor_membership ||= actor.membership_for(membership.account)
    end
  end
end
