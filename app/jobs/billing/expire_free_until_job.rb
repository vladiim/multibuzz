# frozen_string_literal: true

module Billing
  class ExpireFreeUntilJob < ApplicationJob
    queue_as :default

    def perform
      expired_count = expire_accounts

      { expired_count: expired_count }
    end

    private

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
