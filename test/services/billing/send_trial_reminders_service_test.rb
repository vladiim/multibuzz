# frozen_string_literal: true

require "test_helper"

class Billing::SendTrialRemindersServiceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "sends reminder to accounts with trial ending in 3 days" do
    account.update!(
      billing_status: :trialing,
      trial_ends_at: 3.days.from_now,
      billing_email: "test@example.com"
    )

    assert_emails 1 do
      result
    end

    assert result[:success]
    assert_equal 1, result[:sent_count]
  end

  test "does not send to accounts not ending soon" do
    account.update!(
      billing_status: :trialing,
      trial_ends_at: 10.days.from_now,
      billing_email: "test@example.com"
    )

    assert_no_emails do
      result
    end

    assert_equal 0, result[:sent_count]
  end

  test "does not send to non-trialing accounts" do
    account.update!(
      billing_status: :active,
      billing_email: "test@example.com"
    )

    assert_no_emails do
      result
    end
  end

  test "does not send duplicate reminders" do
    account.update!(
      billing_status: :trialing,
      trial_ends_at: 3.days.from_now,
      billing_email: "test@example.com"
    )

    assert_emails 1 do
      service.call
    end

    assert_no_emails do
      service.call
    end
  end

  private

  def result
    @result ||= service.call
  end

  def service
    @service ||= Billing::SendTrialRemindersService.new
  end

  def account
    @account ||= accounts(:one)
  end
end
