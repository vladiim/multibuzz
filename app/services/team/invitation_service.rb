module Team
  class InvitationService < ApplicationService
    EMAIL_REGEX = URI::MailTo::EMAIL_REGEXP

    def initialize(account:, inviter:, email: nil, role: "member", resend_membership: nil)
      @account = account
      @inviter = inviter
      @email = email&.downcase&.strip
      @role = role.to_s
      @resend_membership = resend_membership
    end

    private

    attr_reader :account, :inviter, :email, :role, :resend_membership

    def run
      resend_membership.present? ? handle_resend : handle_new_invitation
    rescue ValidationError => e
      error_result(e.errors)
    end

    # Resend flow
    def handle_resend
      validate_resend!
      regenerate_token
      success_result(membership: resend_membership, invitation_token: invitation_token)
    end

    def validate_resend!
      raise ValidationError, "Can only resend pending invitations" unless resend_membership.pending?
    end

    def regenerate_token
      resend_membership.update!(
        invitation_token_digest: invitation_token_digest,
        invited_at: Time.current,
        invited_by_id: inviter.id,
        invited_by_email: inviter.email
      )
    end

    # New invitation flow
    def handle_new_invitation
      validate_new_invitation!
      success_result(membership: create_invitation, invitation_token: invitation_token)
    end

    def validate_new_invitation!
      validate_email_presence!
      validate_email_format!
      validate_role!
      validate_not_self!
      validate_not_existing_member!
    end

    def validate_email_presence!
      raise ValidationError, "Email is required" if email.blank?
    end

    def validate_email_format!
      raise ValidationError, "Invalid email format" unless email.match?(EMAIL_REGEX)
    end

    def validate_role!
      raise ValidationError, "Cannot invite with owner role" if role == "owner"
    end

    def validate_not_self!
      raise ValidationError, "Cannot invite yourself" if email == inviter.email
    end

    def validate_not_existing_member!
      return unless existing_membership

      message = existing_membership.pending? ? "already has a pending invitation" : "is already a team member"
      raise ValidationError, "This email #{message}"
    end

    def existing_membership
      @existing_membership ||= account.account_memberships.not_deleted.joins(:user).find_by(users: { email: email })
    end

    def create_invitation
      build_membership.tap(&:save!)
    end

    def build_membership
      account.account_memberships.build(
        user: user,
        role: role,
        status: :pending,
        invited_at: Time.current,
        invited_by_id: inviter.id,
        invited_by_email: inviter.email,
        invitation_token_digest: invitation_token_digest
      )
    end

    def user
      @user ||= find_or_create_user
    end

    def find_or_create_user
      User.find_by(email: email) || create_invited_user
    end

    def create_invited_user
      User.create!(email: email, password: SecureRandom.hex(32))
    end

    def invitation_token
      @invitation_token ||= SecureRandom.urlsafe_base64(32)
    end

    def invitation_token_digest
      @invitation_token_digest ||= Digest::SHA256.hexdigest(invitation_token)
    end

    class ValidationError < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = Array(errors)
        super(@errors.first)
      end
    end
  end
end
