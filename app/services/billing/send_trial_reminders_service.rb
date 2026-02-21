# frozen_string_literal: true

module Billing
  class SendTrialRemindersService < ApplicationService
    private

    def run
      sent_count = send_reminders
      success_result(sent_count: sent_count)
    end

    def send_reminders
      accounts_with_trial_ending_soon.count do |account|
        send_reminder_if_not_sent(account)
      end
    end

    def accounts_with_trial_ending_soon
      target_date = TRIAL_REMINDER_DAYS.days.from_now.to_date
      Account
        .where(billing_status: :trialing)
        .where("DATE(trial_ends_at) = ?", target_date)
    end

    def send_reminder_if_not_sent(account)
      return false if already_sent?(account)

      BillingMailer.trial_ending_soon(account).deliver_later
      mark_sent(account)
      true
    end

    def already_sent?(account)
      Rails.cache.exist?(cache_key(account))
    end

    def mark_sent(account)
      Rails.cache.write(cache_key(account), true, expires_in: 30.days)
    end

    def cache_key(account)
      "billing:trial_reminder:#{account.id}"
    end
  end
end
