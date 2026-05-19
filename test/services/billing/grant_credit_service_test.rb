# frozen_string_literal: true

require "test_helper"
require "ostruct"

class Billing::GrantCreditServiceTest < ActiveSupport::TestCase
  test "grants an active credit for the full setup amount" do
    result = service.call

    assert result[:success], "errors: #{result[:errors]}"
    assert_equal ::Billing::GUIDED_SETUP_CREDIT_CENTS, result[:account_credit].amount_cents
    assert_predicate result[:account_credit], :active?
  end

  test "records the plan, source and Stripe transaction on the credit" do
    credit = service.call[:account_credit]

    assert_equal plan, credit.applied_plan
    assert_equal "guided_setup", credit.source
    assert_equal "cbtxn_fake", credit.stripe_balance_transaction_id
  end

  test "credits the customer balance with the full amount" do
    captured = nil
    service(stripe_client: fake_stripe_client { |args| captured = args }).call

    assert_equal "cus_test123", captured[:customer_id]
    assert_equal ::Billing::GUIDED_SETUP_CREDIT_CENTS, captured[:amount_cents]
  end

  test "writes exactly one credit scoped to the account" do
    assert_difference -> { account.account_credits.count }, 1 do
      service.call
    end
  end

  test "returns an error when the account has no Stripe customer" do
    account.update!(stripe_customer_id: nil)

    result = service.call

    assert_not result[:success]
    assert_includes result[:errors], "Account has no Stripe customer"
  end

  test "does not create a credit row without a Stripe customer" do
    account.update!(stripe_customer_id: nil)

    assert_no_difference -> { AccountCredit.count } do
      service.call
    end
  end

  test "surfaces Stripe errors without creating a credit row" do
    error_client = Object.new
    def error_client.credit_customer_balance(customer_id:, amount_cents:)
      raise Stripe::InvalidRequestError.new("balance unavailable", nil)
    end

    result = nil

    assert_no_difference -> { AccountCredit.count } do
      result = service(stripe_client: error_client).call
    end

    assert_not result[:success]
    assert_includes result[:errors].first, "Stripe error"
  end

  private

  def service(stripe_client: nil)
    Billing::GrantCreditService.new(
      account: account,
      plan: plan,
      stripe_client: stripe_client || fake_stripe_client
    )
  end

  def account
    @account ||= accounts(:one).tap { |a| a.update!(stripe_customer_id: "cus_test123") }
  end

  def plan
    @plan ||= plans(:growth)
  end

  def fake_stripe_client(&block)
    FakeStripeClient.new(&block)
  end

  class FakeStripeClient
    def initialize(&on_credit)
      @on_credit = on_credit
    end

    def credit_customer_balance(customer_id:, amount_cents:)
      @on_credit&.call(customer_id: customer_id, amount_cents: amount_cents)
      ::OpenStruct.new(id: "cbtxn_fake")
    end
  end
end
