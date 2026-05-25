# frozen_string_literal: true

require "test_helper"
require "ostruct"

module Billing
  class ActivateSubscriptionServiceTest < ActiveSupport::TestCase
    test "marks the account billing_active" do
      service.call

      assert_predicate account.reload, :billing_active?
    end

    test "stores the Stripe subscription id and stamps subscription_started_at" do
      service.call

      account.reload

      assert_equal "sub_fake", account.stripe_subscription_id
      assert_predicate account.subscription_started_at, :present?
    end

    test "switches the account to the chosen plan" do
      service.call

      assert_equal plan, account.reload.plan
    end

    test "returns the created subscription in the result" do
      result = service.call

      assert result[:success]
      assert_equal "sub_fake", result[:subscription].id
    end

    test "calls Stripe with the account customer and plan price" do
      service.call

      assert_equal "cus_test_activate", stripe.last_create_subscription_args[:customer_id]
      assert_equal plan.stripe_price_id, stripe.last_create_subscription_args[:price_id]
    end

    private

    def service
      Billing::ActivateSubscriptionService.new(account: account, plan: plan, stripe_client: stripe)
    end

    def account
      @account ||= accounts(:one).tap { |a| a.update!(stripe_customer_id: "cus_test_activate") }
    end

    def plan
      @plan ||= plans(:growth).tap { |p| p.update!(stripe_price_id: "price_test_growth") }
    end

    def stripe
      @stripe ||= FakeStripeClient.new
    end

    class FakeStripeClient
      attr_reader :last_create_subscription_args

      def create_subscription(customer_id:, price_id:)
        @last_create_subscription_args = { customer_id: customer_id, price_id: price_id }
        ::OpenStruct.new(id: "sub_fake")
      end
    end
  end
end
