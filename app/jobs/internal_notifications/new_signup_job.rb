# frozen_string_literal: true

module InternalNotifications
  class NewSignupJob < ApplicationJob
    queue_as :default

    def perform(account_id)
      InternalNotificationsMailer.new_signup(
        Account.find(account_id),
        recipient: Rails.application.credentials.dig(:internal_notifications, :signup_recipient)
      ).deliver_now
    end
  end
end
