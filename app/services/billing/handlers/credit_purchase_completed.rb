# frozen_string_literal: true

module Billing
  module Handlers
    # Handles the one-time $1,500 Guided Setup payment. On the payment-mode
    # checkout.session.completed event it grants the non-refundable credit,
    # starts the customer's chosen plan (the credit then covers its invoices),
    # and moves the GuidedSetup engagement into progress.
    class CreditPurchaseCompleted < Base
      def initialize(event_data, stripe_client: nil)
        super(event_data)
        @stripe_client = stripe_client || DefaultStripeClient.new
      end

      private

      attr_reader :stripe_client

      def handle_event
        return plan_not_found_error unless plan
        return if already_processed?

        credit_result = grant_credit
        return credit_result unless credit_result[:success]

        activate_chosen_plan
        account.guided_setup&.mark_in_progress!
        broadcast_confirmation_update
        send_notifications
      end

      def broadcast_confirmation_update
        return unless account.guided_setup&.in_progress?

        Turbo::StreamsChannel.broadcast_replace_to(
          "onboarding_#{account.prefix_id}",
          target: "guided_setup_confirmation",
          partial: "onboarding/confirmation_in_progress",
          locals: { guided_setup: account.guided_setup }
        )
      end

      def send_notifications
        return unless account.guided_setup

        GuidedSetupMailer.welcome(guided_setup: account.guided_setup).deliver_later
        GuidedSetupMailer.internal_notification(guided_setup: account.guided_setup).deliver_later
      end

      # Stripe delivers webhooks at least once; the granted credit is the
      # marker that this purchase was already handled.
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

      def plan_not_found_error
        error_result([ "Plan not found for slug: #{plan_slug.inspect}" ])
      end

      def plan
        @plan ||= Plan.find_by(slug: plan_slug)
      end

      def plan_slug
        metadata[:plan_slug]
      end

      def metadata
        event_object[:metadata] || {}
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
end
