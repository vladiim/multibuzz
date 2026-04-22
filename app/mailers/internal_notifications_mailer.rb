# frozen_string_literal: true

class InternalNotificationsMailer < ApplicationMailer
  def new_signup(account, recipient:)
    return message if recipient.blank?

    @account = account
    @owner = owner_for(account)
    @stats = InternalNotifications::SignupStatsService.new.call
    mail(to: recipient, subject: "New mbuzz signup: #{account.name}")
  end

  private

  def owner_for(account)
    account.account_memberships.owner.accepted.first&.user
  end
end
