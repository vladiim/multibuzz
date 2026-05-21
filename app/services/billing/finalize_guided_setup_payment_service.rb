# frozen_string_literal: true

module Billing
  # Finalises the $1,500 Guided Setup payment once Stripe has charged the
  # customer. Idempotent on AccountCredit (the granted credit is the marker
  # this payment has been processed) so it is safe to call from both the
  # checkout.session.completed webhook handler AND the synchronous success
  # URL verifier -- whichever arrives first wins; the other no-ops.
  #
  # The webhook is canonical in production but can race the Stripe
  # success_url redirect or drop entirely (e.g. local dev without the
  # Stripe CLI listener). The success URL therefore verifies the session
  # itself and calls this service.
  class FinalizeGuidedSetupPaymentService < ApplicationService
    def initialize(account:, plan:, stripe_client: nil)
      @account = account
      @plan = plan
      @stripe_client = stripe_client || DefaultStripeClient.new
    end

    private

    attr_reader :account, :plan, :stripe_client

    def run
      return success_result(already_processed: true) if already_processed?

      credit_result = grant_credit
      return credit_result unless credit_result[:success]

      activate_chosen_plan
      account.guided_setup&.mark_paid!
      broadcast_payment_complete
      send_notifications
      success_result
    end

    def already_processed?
      account.account_credits.exists?(source: ::Billing::GrantCreditService::CREDIT_SOURCE)
    end

    def grant_credit
      Billing::GrantCreditService.new(account: account, plan: plan, stripe_client: stripe_client).call
    end

    def activate_chosen_plan
      subscription = stripe_client.create_subscription(
        customer_id: account.stripe_customer_id,
        price_id: plan.stripe_price_id
      )
      account.update!(
        billing_status: :active,
        stripe_subscription_id: subscription.id,
        plan: plan,
        subscription_started_at: Time.current
      )
    end

    def broadcast_payment_complete
      return unless account.guided_setup&.in_progress?

      Turbo::StreamsChannel.broadcast_replace_to(
        "guided_setup_payment_#{account.prefix_id}",
        target: "payment_complete_state",
        partial: "onboarding/payment_complete_success"
      )
    end

    def send_notifications
      return unless account.guided_setup

      GuidedSetupMailer.welcome(guided_setup: account.guided_setup).deliver_later
      GuidedSetupMailer.internal_notification(guided_setup: account.guided_setup).deliver_later
    end

    class DefaultStripeClient
      def credit_customer_balance(customer_id:, amount_cents:)
        Stripe::Customer.create_balance_transaction(
          customer_id,
          amount: -amount_cents,
          currency: "usd",
          description: "mbuzz Guided Setup credit"
        )
      end

      def create_subscription(customer_id:, price_id:)
        Stripe::Subscription.create(customer: customer_id, items: [ { price: price_id } ])
      end
    end
  end
end
