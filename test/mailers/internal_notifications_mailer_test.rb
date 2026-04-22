# frozen_string_literal: true

require "test_helper"

class InternalNotificationsMailerTest < ActionMailer::TestCase
  test "new_signup is addressed to the supplied recipient" do
    mail = InternalNotificationsMailer.new_signup(account, recipient: "ops@mbuzz.test")

    assert_equal [ "ops@mbuzz.test" ], mail.to
  end

  test "new_signup subject mentions the account name" do
    mail = InternalNotificationsMailer.new_signup(account, recipient: "ops@mbuzz.test")

    assert_includes mail.subject, account.name
  end

  test "new_signup body lists the funnel stats" do
    mail = InternalNotificationsMailer.new_signup(account, recipient: "ops@mbuzz.test")

    assert_match(/Total accounts/i, mail.body.encoded)
  end

  test "new_signup is a no-op when recipient is nil" do
    mail = InternalNotificationsMailer.new_signup(account, recipient: nil)

    assert_predicate mail.to.to_a, :empty?
  end

  test "new_signup is a no-op when recipient is blank" do
    mail = InternalNotificationsMailer.new_signup(account, recipient: "")

    assert_predicate mail.to.to_a, :empty?
  end

  private

  def account = @account ||= accounts(:one)
end
