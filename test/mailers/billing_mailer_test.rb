require "test_helper"

class BillingMailerTest < ActionMailer::TestCase
  # Payment & Subscription emails
  test "payment_failed sends to billing email" do
    email = BillingMailer.payment_failed(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /payment failed/i, email.subject
  end

  test "payment_succeeded sends confirmation" do
    email = BillingMailer.payment_succeeded(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /payment.*successful/i, email.subject
  end

  test "events_locked warns about locked events" do
    email = BillingMailer.events_locked(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /records.*locked/i, email.subject
  end

  test "events_unlocked confirms restoration" do
    email = BillingMailer.events_unlocked(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /events.*unlocked|restored/i, email.subject
  end

  test "subscription_created sends welcome" do
    email = BillingMailer.subscription_created(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /subscription|welcome/i, email.subject
  end

  test "subscription_cancelled confirms cancellation" do
    email = BillingMailer.subscription_cancelled(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /cancel/i, email.subject
  end

  # Free Until emails
  test "free_until_granted confirms free access" do
    account.update!(free_until: 30.days.from_now)
    email = BillingMailer.free_until_granted(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /free.*access/i, email.subject
  end

  test "free_until_expiring_soon sends reminder" do
    account.update!(free_until: 5.days.from_now)
    email = BillingMailer.free_until_expiring_soon(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /expir|ending/i, email.subject
  end

  test "free_until_expired notifies expiration" do
    email = BillingMailer.free_until_expired(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /expired|ended/i, email.subject
  end

  # Usage emails
  test "usage_warning sends at threshold" do
    email = BillingMailer.usage_warning(account, usage_percentage: 80)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /usage|approaching/i, email.subject
  end

  test "usage_limit_reached sends at 100%" do
    email = BillingMailer.usage_limit_reached(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /limit.*reached/i, email.subject
  end

  # Trial emails
  test "trial_started sends welcome" do
    email = BillingMailer.trial_started(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /trial/i, email.subject
  end

  test "trial_ending_soon sends reminder" do
    account.update!(trial_ends_at: 3.days.from_now)
    email = BillingMailer.trial_ending_soon(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /trial.*end/i, email.subject
  end

  test "trial_expired notifies expiration" do
    email = BillingMailer.trial_expired(account)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [account.billing_email], email.to
    assert_match /trial.*expired/i, email.subject
  end

  private

  def account
    @account ||= accounts(:one).tap do |a|
      a.update!(billing_email: "billing@example.com")
    end
  end
end
