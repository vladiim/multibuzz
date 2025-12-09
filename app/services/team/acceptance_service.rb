module Team
  class AcceptanceService < ApplicationService
    EXPIRY_DAYS = 7

    def initialize(token:, current_user: nil, password: nil, password_confirmation: nil, lookup_only: false)
      @token = token
      @current_user = current_user
      @password = password
      @password_confirmation = password_confirmation
      @lookup_only = lookup_only
    end

    private

    attr_reader :token, :current_user, :password, :password_confirmation, :lookup_only

    def run
      return error_with_code(:not_found, "Invitation not found") unless membership
      return error_with_code(:expired, "Invitation has expired") if expired?
      return error_with_code(:already_accepted, "Invitation already accepted") if membership.accepted?
      return success_result(membership: membership) if lookup_only

      accept_invitation
    end

    def accept_invitation
      current_user.present? ? accept_for_logged_in_user : accept_with_password
    end

    def accept_for_logged_in_user
      return error_with_code(:wrong_user, "Invitation is for a different user") unless correct_user?

      complete_acceptance
    end

    def accept_with_password
      return password_validation_error unless valid_password?

      set_user_password
      complete_acceptance
    end

    def complete_acceptance
      membership.update!(
        status: :accepted,
        accepted_at: Time.current,
        invitation_token_digest: nil
      )
      success_result(membership: membership)
    end

    def correct_user?
      current_user.id == membership.user_id
    end

    def valid_password?
      password.present? &&
        password.length >= 8 &&
        password == password_confirmation
    end

    def password_validation_error
      errors = []
      errors << "Password is required" if password.blank?
      errors << "Password must be at least 8 characters" if password.present? && password.length < 8
      errors << "Password confirmation doesn't match" if password != password_confirmation

      error_with_code(:validation_error, errors)
    end

    def set_user_password
      membership.user.update!(password: password)
    end

    def membership
      @membership ||= find_membership_by_token
    end

    def find_membership_by_token
      return nil if token.blank?

      AccountMembership.find_by(invitation_token_digest: token_digest)
    end

    def token_digest
      Digest::SHA256.hexdigest(token)
    end

    def expired?
      membership.invited_at < EXPIRY_DAYS.days.ago
    end

    def error_with_code(code, messages)
      { success: false, error_code: code, errors: Array(messages) }
    end
  end
end
