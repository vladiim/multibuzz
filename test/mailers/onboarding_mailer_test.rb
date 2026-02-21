# frozen_string_literal: true

require "test_helper"

class OnboardingMailerTest < ActionMailer::TestCase
  test "welcome sends to user with API key subject" do
    email = OnboardingMailer.welcome(account: account, user: user)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [ user.email ], email.to
    assert_match /welcome/i, email.subject
    assert_match /api key/i, email.subject
  end

  private

  def account
    @account ||= accounts(:one)
  end

  def user
    @user ||= users(:one)
  end
end
