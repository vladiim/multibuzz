# frozen_string_literal: true

module Billing
  module Handlers
    # Thin orchestrator for the $1,500 Guided Setup payment.
    # checkout.session.completed (mode=payment) -> grant credit -> activate
    # subscription -> mark engagement paid -> broadcast -> notify.
    #
    # Idempotent on AccountCredit: the success-URL verifier may invoke this
    # synchronously before the webhook arrives. Whichever path lands first
    # wins; the other is a no-op via already_processed?.
    class CreditPurchaseCompleted < Base
      def initialize(event_data, stripe_client: nil)
        super(event_data)
        @stripe_client = stripe_client
      end

      private

      attr_reader :stripe_client

      def handle_event
        return plan_not_found_error unless plan
        return if already_processed?
        return credit_result unless credit_result[:success]

        activation_result
        finalize_engagement
        deliver_notifications
      end

      def plan_not_found_error
        error_result([ "Plan not found for slug: #{plan_slug.inspect}" ])
      end

      def already_processed?
        account.account_credits.exists?(source: ::Billing::GrantCreditService::CREDIT_SOURCE)
      end

      def credit_result
        @credit_result ||= Billing::GrantCreditService.new(account: account, plan: plan, stripe_client: stripe_client).call
      end

      def activation_result
        @activation_result ||= Billing::ActivateSubscriptionService.new(account: account, plan: plan, stripe_client: stripe_client).call
      end

      def finalize_engagement
        return unless guided_setup

        guided_setup.mark_paid!
        broadcast_payment_complete
      end

      # Stripe's success_url redirect races this webhook. The customer may
      # be sitting on payment_complete in the processing state. Broadcast
      # the success partial so the page updates without a refresh.
      def broadcast_payment_complete
        return unless guided_setup.in_progress?

        Turbo::StreamsChannel.broadcast_replace_to(
          "guided_setup_payment_#{account.prefix_id}",
          target: "payment_complete_state",
          partial: "onboarding/payment_complete_success"
        )
      end

      def deliver_notifications
        return unless guided_setup

        GuidedSetupMailer.welcome(guided_setup: guided_setup).deliver_later
        GuidedSetupMailer.internal_notification(guided_setup: guided_setup).deliver_later
      end

      def guided_setup
        @guided_setup ||= account.guided_setup
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
    end
  end
end
