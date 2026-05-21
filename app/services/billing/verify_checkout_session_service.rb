# frozen_string_literal: true

module Billing
  # Server-side verification of a Stripe Checkout Session on the success
  # URL. Webhooks are canonical in production but they race the success
  # redirect and don't fire at all in local dev without the Stripe CLI
  # listener. This service retrieves the session directly, confirms the
  # customer paid AND that the session belongs to this account, then
  # invokes the same CreditPurchaseCompleted handler the webhook would
  # have. The handler is idempotent on AccountCredit -- if the webhook
  # already finalised the payment, this no-ops.
  class VerifyCheckoutSessionService < ApplicationService
    def initialize(session_id:, account:, stripe_client: nil, handler_stripe_client: nil)
      @session_id = session_id
      @account = account
      @stripe_client = stripe_client || DefaultStripeClient.new
      @handler_stripe_client = handler_stripe_client
    end

    private

    attr_reader :session_id, :account, :stripe_client, :handler_stripe_client

    def run
      return error_result([ "Stripe session not paid" ]) unless session_paid?
      return error_result([ "Stripe session belongs to a different account" ]) unless session_account_matches?

      Billing::Handlers::CreditPurchaseCompleted.new(handler_event_data, **handler_kwargs).call
    end

    def session_paid?
      session.payment_status == "paid"
    end

    def session_account_matches?
      metadata && metadata[:account_id].to_s == account.prefix_id
    end

    def handler_event_data
      { data: { object: { customer: session.customer, metadata: metadata } } }
    end

    def handler_kwargs
      handler_stripe_client ? { stripe_client: handler_stripe_client } : {}
    end

    def metadata
      @metadata ||= session.metadata&.to_h&.symbolize_keys
    end

    def session
      @session ||= stripe_client.retrieve_session(session_id)
    end

    class DefaultStripeClient
      def retrieve_session(session_id)
        Stripe::Checkout::Session.retrieve(session_id)
      end
    end
  end
end
