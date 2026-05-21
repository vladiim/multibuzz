# frozen_string_literal: true

require "test_helper"
require "ostruct"

module Billing
  class VerifyCheckoutSessionServiceTest < ActiveSupport::TestCase
    test "finalises a paid session for the matching account" do
      guided_setup

      assert_difference -> { account.account_credits.count }, 1 do
        service.call
      end

      assert_predicate guided_setup.reload, :in_progress?
    end

    test "returns an error when Stripe says the session is not paid" do
      stripe.payment_status = "unpaid"

      result = service.call

      assert_not result[:success]
      assert_includes result[:errors].first, "not paid"
    end

    test "returns an error when the session belongs to a different account" do
      stripe.account_id_metadata = "acct_someone_else"

      result = service.call

      assert_not result[:success]
      assert_includes result[:errors].first, "different account"
    end

    test "is idempotent when the credit has already been granted" do
      service.call

      assert_no_difference -> { account.account_credits.count } do
        service.call
      end
    end

    test "delegates account-not-found errors from the handler" do
      account.update!(stripe_customer_id: nil)

      result = service.call

      assert_not result[:success]
      assert_includes result[:errors].first, "Account not found"
    end

    private

    def service
      Billing::VerifyCheckoutSessionService.new(
        session_id: "cs_test_verify",
        account: account,
        stripe_client: stripe,
        handler_stripe_client: handler_stripe
      )
    end

    def account
      @account ||= accounts(:one).tap { |a| a.update!(stripe_customer_id: "cus_test_verify") }
    end

    def guided_setup
      @guided_setup ||= GuidedSetup.create!(account: account, kickoff_booked_at: Time.current)
    end

    def stripe
      @stripe ||= FakeStripeSessionClient.new(account_id: account.prefix_id)
    end

    def handler_stripe
      @handler_stripe ||= FakeHandlerStripeClient.new
    end

    class FakeStripeSessionClient
      attr_accessor :payment_status, :account_id_metadata

      def initialize(account_id:)
        @payment_status = "paid"
        @account_id_metadata = account_id
      end

      def retrieve_session(_session_id)
        ::OpenStruct.new(
          customer: "cus_test_verify",
          payment_status: payment_status,
          metadata: { account_id: account_id_metadata, plan_slug: "growth", guided_setup: "true" }
        )
      end
    end

    class FakeHandlerStripeClient
      def credit_customer_balance(customer_id:, amount_cents:)
        ::OpenStruct.new(id: "cbtxn_fake", customer_id: customer_id, amount_cents: amount_cents)
      end

      def create_subscription(customer_id:, price_id:)
        ::OpenStruct.new(id: "sub_fake", customer_id: customer_id, price_id: price_id)
      end
    end
  end
end
