# frozen_string_literal: true

require "test_helper"

class GuidedSetupMailerTest < ActionMailer::TestCase
  # --- welcome (to the customer) ---

  test "welcome sends to the account's billing email when set" do
    account.update!(billing_email: "buyer@example.com")

    assert_equal [ "buyer@example.com" ], welcome_email.to
  end

  test "welcome falls back to the account owner when no billing email is set" do
    account.update!(billing_email: nil)

    assert_equal [ owner.email ], welcome_email.to
  end

  test "welcome subject mentions Guided Setup" do
    assert_match(/Guided Setup/i, welcome_email.subject)
  end

  test "welcome body covers the kickoff and install touchpoints" do
    body = welcome_email.body.encoded

    assert_match(/kickoff/i, body)
    assert_match(/install/i, body)
  end

  test "welcome body covers the integration and training touchpoints" do
    body = welcome_email.body.encoded

    assert_match(/integration/i, body)
    assert_match(/training/i, body)
  end

  # --- internal_notification (to the mbuzz team) ---

  test "internal_notification delivers to the configured internal email" do
    assert_predicate notification_email, :present?, "notifications.internal_email must be set in credentials"
    assert_equal [ notification_email ], internal_email.to
  end

  test "internal_notification subject identifies the account by prefix id" do
    assert_includes internal_email.subject, account.prefix_id
    assert_match(/Guided Setup/i, internal_email.subject)
  end

  test "internal_notification body includes the integration target and chosen plan" do
    body = internal_email.body.encoded

    assert_includes body, "meta"
    assert_includes body, "Growth"
  end

  private

  def welcome_email
    @welcome_email ||= GuidedSetupMailer.welcome(guided_setup: guided_setup)
  end

  def internal_email
    @internal_email ||= GuidedSetupMailer.internal_notification(guided_setup: guided_setup)
  end

  def guided_setup
    @guided_setup ||= GuidedSetup.create!(
      account: account,
      status: :in_progress,
      integration_target: :meta,
      accepted_at: Time.current
    )
  end

  def account
    @account ||= accounts(:one).tap { |a| a.update!(plan: plans(:growth)) }
  end

  def owner
    @owner ||= account.account_memberships.owner.accepted.first.user
  end

  def notification_email
    @notification_email ||= Rails.application.credentials.dig(:notifications, :internal_email)
  end
end
