# frozen_string_literal: true

module Accounts
  class CreationService < ApplicationService
    def initialize(user:, name:)
      @user = user
      @name = name&.strip
    end

    private

    attr_reader :user, :name

    def run
      return validation_errors unless valid?

      create_account_with_ownership
    end

    def valid?
      name.present?
    end

    def validation_errors
      error_result(["Name can't be blank"])
    end

    def create_account_with_ownership
      ActiveRecord::Base.transaction do
        account = create_account
        create_owner_membership(account)
        success_result(account: account)
      end
    rescue ActiveRecord::RecordInvalid => e
      error_result(e.record.errors.full_messages)
    end

    def create_account
      Account.create!(name: name, slug: unique_slug)
    end

    def create_owner_membership(account)
      account.account_memberships.create!(
        user: user,
        role: :owner,
        status: :accepted,
        accepted_at: Time.current
      )
    end

    def unique_slug
      base_slug = name.parameterize
      return base_slug unless Account.exists?(slug: base_slug)

      "#{base_slug}-#{SecureRandom.hex(4)}"
    end
  end
end
