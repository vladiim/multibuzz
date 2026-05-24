# frozen_string_literal: true

module Billing
  # Starts a Stripe subscription for the account on the chosen plan and
  # marks the account billing_active. Extracted from CreditPurchaseCompleted
  # so the handler stays a thin orchestrator and so the test surface for
  # "what does the activation step do" is its own file.
  class ActivateSubscriptionService < ApplicationService
    def initialize(account:, plan:, stripe_client: nil)
      @account = account
      @plan = plan
      @stripe_client = stripe_client || DefaultStripeClient.new
    end

    private

    attr_reader :account, :plan, :stripe_client

    def run
      account.update!(activation_attributes)
      success_result(subscription: subscription)
    end

    def activation_attributes
      {
        billing_status: :active,
        stripe_subscription_id: subscription.id,
        plan: plan,
        subscription_started_at: Time.current
      }
    end

    def subscription
      @subscription ||= stripe_client.create_subscription(
        customer_id: account.stripe_customer_id,
        price_id: plan.stripe_price_id
      )
    end

    class DefaultStripeClient
      def create_subscription(customer_id:, price_id:)
        Stripe::Subscription.create(customer: customer_id, items: [ { price: price_id } ])
      end
    end
  end
end
