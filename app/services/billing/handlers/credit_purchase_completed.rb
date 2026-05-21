# frozen_string_literal: true

module Billing
  module Handlers
    # Handles the one-time $1,500 Guided Setup payment from the
    # checkout.session.completed webhook. Looks up the chosen plan from the
    # session metadata and delegates to FinalizeGuidedSetupPaymentService,
    # which is idempotent on AccountCredit -- if the success URL verifier
    # already finalised the payment, this no-ops.
    class CreditPurchaseCompleted < Base
      def initialize(event_data, stripe_client: nil)
        super(event_data)
        @stripe_client = stripe_client || Billing::FinalizeGuidedSetupPaymentService::DefaultStripeClient.new
      end

      private

      attr_reader :stripe_client

      def handle_event
        return plan_not_found_error unless plan

        Billing::FinalizeGuidedSetupPaymentService.new(
          account: account,
          plan: plan,
          stripe_client: stripe_client
        ).call
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
    end
  end
end
