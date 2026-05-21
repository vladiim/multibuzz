# frozen_string_literal: true

require "test_helper"

class Onboarding::PaymentLinksControllerTest < ActionDispatch::IntegrationTest
  test "signs in the account owner and lands on payment_setup for a valid token" do
    token = guided_setup.mint_payment_token!

    get onboarding_payment_link_path(token: token)

    assert_equal owner.id, session[:user_id]
    assert_redirected_to onboarding_payment_setup_path
  end

  test "redirects to login with an alert when the token is unknown" do
    get onboarding_payment_link_path(token: "does-not-exist")

    assert_redirected_to login_path
    assert_match(/invalid or has expired/, flash[:alert])
  end

  test "redirects to login with an alert when the token has expired" do
    token = guided_setup.mint_payment_token!
    guided_setup.update_columns(payment_token_expires_at: 1.minute.ago)

    get onboarding_payment_link_path(token: token)

    assert_redirected_to login_path
    assert_match(/invalid or has expired/, flash[:alert])
  end

  private

  def account = @account ||= accounts(:one)
  def owner = @owner ||= account.account_memberships.owner.accepted.first.user

  def guided_setup
    @guided_setup ||= GuidedSetup.create!(account: account, kickoff_booked_at: Time.current)
  end
end
