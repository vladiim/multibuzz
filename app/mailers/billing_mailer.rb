class BillingMailer < ApplicationMailer
  # Payment & Subscription
  def payment_failed(account)
    @account = account
    mail(to: recipient(account), subject: "Payment failed - action required")
  end

  def payment_succeeded(account)
    @account = account
    mail(to: recipient(account), subject: "Payment successful - thank you!")
  end

  def events_locked(account)
    @account = account
    mail(to: recipient(account), subject: "Records locked - update payment to restore access")
  end

  def events_unlocked(account)
    @account = account
    mail(to: recipient(account), subject: "Records restored - your data is now accessible")
  end

  def subscription_created(account)
    @account = account
    mail(to: recipient(account), subject: "Welcome to mbuzz!")
  end

  def subscription_cancelled(account)
    @account = account
    mail(to: recipient(account), subject: "Subscription cancelled")
  end

  # Free Until
  def free_until_granted(account)
    @account = account
    @days_remaining = account.days_until_free_expires
    mail(to: recipient(account), subject: "Free access granted to mbuzz")
  end

  def free_until_expiring_soon(account)
    @account = account
    @days_remaining = account.days_until_free_expires
    mail(to: recipient(account), subject: "Your free access is ending soon")
  end

  def free_until_expired(account)
    @account = account
    mail(to: recipient(account), subject: "Free access has ended")
  end

  # Usage
  def usage_warning(account, usage_percentage:)
    @account = account
    @usage_percentage = usage_percentage
    mail(to: recipient(account), subject: "Approaching your record limit (#{usage_percentage}% used)")
  end

  def usage_limit_reached(account)
    @account = account
    mail(to: recipient(account), subject: "Record limit reached - upgrade to continue tracking")
  end

  # Trial
  def trial_started(account)
    @account = account
    mail(to: recipient(account), subject: "Your trial has started!")
  end

  def trial_ending_soon(account)
    @account = account
    @days_remaining = days_until_trial_ends(account)
    mail(to: recipient(account), subject: "Your trial ends in #{@days_remaining} days")
  end

  def trial_expired(account)
    @account = account
    mail(to: recipient(account), subject: "Trial expired - subscribe to continue")
  end

  private

  def recipient(account)
    account.billing_email
  end

  def days_until_trial_ends(account)
    return nil unless account.trial_ends_at

    ((account.trial_ends_at - Time.current) / 1.day).ceil
  end
end
