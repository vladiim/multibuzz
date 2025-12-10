# frozen_string_literal: true

class SignupService < ApplicationService
  def initialize(email:, password:, account_name:)
    @email = email&.strip&.downcase
    @password = password
    @account_name = account_name&.strip
  end

  private

  attr_reader :email, :password, :account_name

  def run
    return validation_errors unless valid?

    create_user_and_account
  end

  def valid?
    email.present? && password.present? && account_name.present?
  end

  def validation_errors
    errors = []
    errors << "Email can't be blank" if email.blank?
    errors << "Password can't be blank" if password.blank?
    errors << "Company name can't be blank" if account_name.blank?
    error_result(errors)
  end

  def create_user_and_account
    ActiveRecord::Base.transaction do
      user = create_user
      account = create_account
      create_owner_membership(user, account)
      api_key_result = create_test_api_key(account)
      success_result(
        user: user,
        account: account,
        plaintext_api_key: api_key_result[:plaintext_key]
      )
    end
  end

  def create_user
    User.create!(email: email, password: password)
  end

  def create_account
    Account.create!(name: account_name, slug: unique_slug)
  end

  def create_owner_membership(user, account)
    account.account_memberships.create!(
      user: user,
      role: :owner,
      status: :accepted,
      accepted_at: Time.current
    )
  end

  def create_test_api_key(account)
    ApiKeys::GenerationService.new(account, environment: :test).call
  end

  def unique_slug
    base_slug = account_name.parameterize
    return base_slug unless Account.exists?(slug: base_slug)

    "#{base_slug}-#{SecureRandom.hex(4)}"
  end
end
