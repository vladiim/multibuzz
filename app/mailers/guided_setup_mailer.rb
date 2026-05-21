# frozen_string_literal: true

class GuidedSetupMailer < ApplicationMailer
  def welcome(guided_setup:)
    @guided_setup = guided_setup
    @account = guided_setup.account
    @recipient_email = customer_email(@account)

    mail(
      to: @recipient_email,
      subject: "Welcome to mbuzz Guided Setup"
    )
  end

  def internal_notification(guided_setup:)
    @guided_setup = guided_setup
    @account = guided_setup.account

    mail(
      to: internal_notification_email,
      subject: "[mbuzz] Guided Setup purchased by #{@account.prefix_id}"
    )
  end

  def kickoff_booked(guided_setup:)
    @guided_setup = guided_setup
    @account = guided_setup.account
    @scheduling_form = SchedulingPreferencesPresenter.from(guided_setup.scheduling_preferences)
    @customer_email = customer_email(@account)

    mail(
      to: internal_notification_email,
      subject: "[mbuzz] Kickoff booked: #{@account.name} (#{@account.prefix_id})"
    )
  end

  private

  def customer_email(account)
    account.billing_email.presence ||
      account.account_memberships.owner.accepted.first&.user&.email
  end
end
