# frozen_string_literal: true

module Billing
  class ExpireFreeUntilService < ApplicationService
    private

    def run
      count = expire_accounts

      success_result(expired_count: count)
    end

    def expire_accounts
      count = expired_accounts.count
      expired_accounts.find_each(&:expire!)
      count
    end

    def expired_accounts
      Account
        .where(billing_status: :free_until)
        .where("free_until <= ?", Time.current)
    end
  end
end
