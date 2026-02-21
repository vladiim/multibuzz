# frozen_string_literal: true

module Team
  class RoleChangeService < ApplicationService
    VALID_ROLES = %w[viewer member admin owner].freeze

    VALIDATIONS = {
      membership_missing?: [ :not_found, "Membership not found" ],
      invalid_role?: [ :validation, "Invalid role" ],
      pending_membership?: [ :validation, "Cannot change role of pending membership" ],
      unauthorized?: [ :forbidden, "Not authorized to change roles" ],
      self_change?: [ :validation, "Cannot change your own role" ],
      promoting_to_owner_without_permission?: [ :forbidden, "Only owners can assign owner role" ],
      admin_demoting_admin?: [ :forbidden, "Cannot change the role of another admin" ]
    }.freeze

    def initialize(actor:, membership:, new_role:)
      @actor = actor
      @membership = membership
      @new_role = new_role.to_s
    end

    private

    attr_reader :actor, :membership, :new_role

    def run
      validation_error || update_role
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

    def invalid_role?
      !VALID_ROLES.include?(new_role)
    end

    def pending_membership?
      !membership.accepted?
    end

    def unauthorized?
      !actor_membership&.admin? && !actor_membership&.owner?
    end

    def self_change?
      actor.id == membership.user_id
    end

    def promoting_to_owner_without_permission?
      new_role == "owner" && !actor_membership&.owner?
    end

    def admin_demoting_admin?
      actor_admin_not_owner? && target_admin_or_owner?
    end

    def actor_admin_not_owner?
      actor_membership&.admin? && !actor_membership&.owner?
    end

    def target_admin_or_owner?
      membership.admin? || membership.owner?
    end

    def update_role
      membership.update!(role: new_role)
      success_result
    end

    def actor_membership
      @actor_membership ||= actor.membership_for(membership.account)
    end
  end
end
