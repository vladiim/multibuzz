# frozen_string_literal: true

module Billing
  class SendFreeUntilRemindersService < ApplicationService
    REMINDER_WINDOWS = [
      { days: FREE_UNTIL_WARNING_DAYS, cache_key: "7day" },
      { days: FREE_UNTIL_FINAL_REMINDER_DAYS, cache_key: "1day" }
    ].freeze

    private

    def run
      sent_count = 0

      REMINDER_WINDOWS.each do |window|
        sent_count += send_reminders_for_window(window)
      end

      success_result(sent_count: sent_count)
    end

    def send_reminders_for_window(window)
      accounts_expiring_in(window[:days]).count do |account|
        send_reminder_if_not_sent(account, window[:cache_key])
      end
    end

    def accounts_expiring_in(days)
      # Match accounts expiring on exactly this day (within 24 hour window)
      target_date = days.days.from_now.to_date
      Account
        .where(billing_status: :free_until)
        .where("DATE(free_until) = ?", target_date)
    end

    def send_reminder_if_not_sent(account, cache_key)
      return false if already_sent?(account, cache_key)

      BillingMailer.free_until_expiring_soon(account).deliver_later
      mark_sent(account, cache_key)
      true
    end

    def already_sent?(account, cache_key)
      Rails.cache.exist?(reminder_cache_key(account, cache_key))
    end

    def mark_sent(account, cache_key)
      Rails.cache.write(
        reminder_cache_key(account, cache_key),
        true,
        expires_in: 30.days
      )
    end

    def reminder_cache_key(account, cache_key)
      "billing:free_until_reminder:#{account.id}:#{cache_key}"
    end
  end
end
