# frozen_string_literal: true

require "test_helper"
require "ostruct"

module Billing
  module Handlers
    class CreditPurchaseCompletedTest < ActiveSupport::TestCase
      include ActiveJob::TestHelper
      test "grants a Guided Setup credit" do
        assert_difference -> { account.account_credits.count }, 1 do
          handler.call
        end
      end

      test "starts the chosen plan's subscription" do
        handler.call

        account.reload

        assert_predicate account, :billing_active?
        assert_equal "sub_fake", account.stripe_subscription_id
        assert_equal plan, account.plan
      end

      test "moves the GuidedSetup engagement in progress" do
        guided_setup

        handler.call

        assert_predicate guided_setup.reload, :in_progress?
      end

      test "sends the customer welcome and internal notification emails" do
        guided_setup

        assert_enqueued_jobs 2, only: ActionMailer::MailDeliveryJob do
          handler.call
        end
      end

      test "clears the payment token once the credit lands" do
        guided_setup.mint_payment_token!

        handler.call

        assert_nil guided_setup.reload.payment_token
      end

      test "skips the emails when no GuidedSetup engagement exists" do
        assert_no_enqueued_jobs only: ActionMailer::MailDeliveryJob do
          handler.call
        end
      end

      test "returns an error when the plan is not found" do
        result = handler(plan_slug: "nonexistent").call

        assert_not result[:success]
        assert_includes result[:errors].first, "Plan not found"
      end

      test "returns an error when the account is not found" do
        account.update!(stripe_customer_id: nil)

        result = handler.call

        assert_not result[:success]
        assert_includes result[:errors].first, "Account not found"
      end

      test "is idempotent once the credit has been granted" do
        handler.call

        assert_no_difference -> { account.account_credits.count } do
          handler.call
        end
      end

      private

      def handler(plan_slug: "growth")
        Billing::Handlers::CreditPurchaseCompleted.new(
          event_data(plan_slug), stripe_client: fake_stripe_client
        )
      end

      def fake_stripe_client
        @fake_stripe_client ||= FakeStripeClient.new
      end

      def account
        @account ||= accounts(:one).tap { |a| a.update!(stripe_customer_id: "cus_test123") }
      end

      def plan
        @plan ||= plans(:growth)
      end

      def guided_setup
        @guided_setup ||= GuidedSetup.create!(account: account)
      end

      def event_data(plan_slug)
        {
          id: "evt_test",
          type: "checkout.session.completed",
          data: {
            object: {
              id: "cs_test",
              customer: "cus_test123",
              mode: "payment",
              metadata: { account_id: account.prefix_id, guided_setup: "true", plan_slug: plan_slug }
            }
          }
        }
      end

      class FakeStripeClient
        def credit_customer_balance(customer_id:, amount_cents:)
          ::OpenStruct.new(id: "cbtxn_fake", customer_id: customer_id, amount_cents: amount_cents)
        end

        def create_subscription(customer_id:, price_id:)
          ::OpenStruct.new(id: "sub_fake", customer_id: customer_id, price_id: price_id)
        end
      end
    end
  end
end
