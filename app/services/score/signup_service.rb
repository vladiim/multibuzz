# frozen_string_literal: true

module Score
  # Creates a user account from the score assessment flow.
  # Derives account name from email domain (no company name field needed).
  # Optionally claims an unclaimed assessment via claim_token.
  class SignupService < ApplicationService
    attr_reader :email, :password, :company_name, :claim_token

    def initialize(email:, password:, company_name: nil, claim_token: nil)
      @email = email&.strip&.downcase
      @password = password
      @company_name = company_name&.strip.presence
      @claim_token = claim_token
    end

    private

    def run
      return validation_errors unless valid?

      create_user_and_account
    end

    def valid?
      email.present? && password.present?
    end

    def validation_errors
      errors = []
      errors << "Email can't be blank" if email.blank?
      errors << "Password can't be blank" if password.blank?
      error_result(errors)
    end

    def create_user_and_account
      ActiveRecord::Base.transaction do
        user = User.create!(email: email, password: password)
        account = Account.create!(name: account_name, slug: unique_slug)
        create_owner_membership(user, account)
        claim_assessment(user)
        success_result(user: user, account: account)
      end
    end

    def create_owner_membership(user, account)
      account.account_memberships.create!(
        user: user,
        role: :owner,
        status: :accepted,
        accepted_at: Time.current
      )
    end

    def claim_assessment(user)
      return if claim_token.blank?

      assessment = ScoreAssessment.find_by(claim_token: claim_token)
      return unless assessment

      assessment.update!(user: user, claim_token: nil)
    end

    def account_name
      return company_name if company_name

      domain = email.split("@").last
      domain.presence || email
    end

    def unique_slug
      base_slug = account_name.parameterize
      return base_slug unless Account.exists?(slug: base_slug)

      "#{base_slug}-#{SecureRandom.hex(4)}"
    end
  end
end
