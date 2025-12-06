require "test_helper"

class Billing::SendFreeUntilRemindersServiceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  test "sends reminder to accounts expiring in 7 days" do
    account.update!(
      billing_status: :free_until,
      free_until: 7.days.from_now,
      billing_email: "test@example.com"
    )

    assert_emails 1 do
      result
    end

    assert result[:success]
    assert_equal 1, result[:sent_count]
  end

  test "sends reminder to accounts expiring in 1 day" do
    account.update!(
      billing_status: :free_until,
      free_until: 1.day.from_now,
      billing_email: "test@example.com"
    )

    assert_emails 1 do
      result
    end

    assert result[:success]
  end

  test "does not send to accounts not expiring soon" do
    account.update!(
      billing_status: :free_until,
      free_until: 30.days.from_now,
      billing_email: "test@example.com"
    )

    assert_no_emails do
      result
    end

    assert result[:success]
    assert_equal 0, result[:sent_count]
  end

  test "does not send to non-free_until accounts" do
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
      billing_status: :free_until,
      free_until: 7.days.from_now,
      billing_email: "test@example.com"
    )

    # First run sends
    assert_emails 1 do
      service.call
    end

    # Second run within same day does not send
    assert_no_emails do
      service.call
    end
  end

  private

  def result
    @result ||= service.call
  end

  def service
    @service ||= Billing::SendFreeUntilRemindersService.new
  end

  def account
    @account ||= accounts(:one)
  end
end
