# frozen_string_literal: true

module Billing
  # Builds the one-time $1,500 Stripe Checkout for Guided Setup. It runs in
  # `payment` mode (not a subscription) -- on completion the webhook grants the
  # credit and starts the customer's chosen plan, which rides along in the
  # session metadata.
  class CreditCheckoutService < ApplicationService
    def initialize(account:, plan_slug:, urls:, stripe_client: nil)
      @account = account
      @plan_slug = plan_slug
      @urls = urls
      @stripe_client = stripe_client || DefaultStripeClient.new
    end

    private

    attr_reader :account, :plan_slug, :urls, :stripe_client

    def run
      return validation_error if invalid?

      ensure_stripe_customer
      create_checkout_session
    end

    def invalid?
      !plan || plan.free? || plan.stripe_price_id.blank?
    end

    def validation_error
      return error_result([ "Plan not found" ]) unless plan
      return error_result([ "Cannot checkout free plan" ]) if plan.free?

      error_result([ "Plan not configured for billing" ])
    end

    def ensure_stripe_customer
      return if account.stripe_customer_id.present?

      account.update!(stripe_customer_id: new_customer.id)
    end

    def create_checkout_session
      success_result(session_id: checkout_session.id, checkout_url: checkout_session.url)
    rescue Stripe::StripeError => e
      error_result([ "Stripe error: #{e.message}" ])
    end

    def new_customer
      @new_customer ||= stripe_client.create_customer(
        email: account.billing_email,
        metadata: { account_id: account.prefix_id }
      )
    end

    def checkout_session
      @checkout_session ||= stripe_client.create_checkout_session(session_params)
    end

    def session_params
      {
        customer: account.stripe_customer_id,
        mode: "payment",
        line_items: line_items,
        # Stripe substitutes {CHECKOUT_SESSION_ID} at redirect time. The
        # success URL handler uses the session id to verify payment
        # synchronously instead of waiting for the webhook (necessary in
        # local dev without the Stripe CLI and a useful production
        # fallback when the webhook races or drops).
        success_url: "#{urls[:success]}?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: urls[:cancel],
        metadata: session_metadata
      }
    end

    def line_items
      [ {
        quantity: 1,
        price_data: {
          currency: "usd",
          unit_amount: ::Billing::GUIDED_SETUP_CREDIT_CENTS,
          product_data: { name: "mbuzz Guided Setup" }
        }
      } ]
    end

    def session_metadata
      {
        account_id: account.prefix_id,
        guided_setup: "true",
        plan_slug: plan.slug
      }
    end

    def plan
      @plan ||= Plan.find_by(slug: plan_slug)
    end

    class DefaultStripeClient
      def create_customer(email:, metadata:)
        Stripe::Customer.create(email: email, metadata: metadata)
      end

      def create_checkout_session(params)
        Stripe::Checkout::Session.create(params)
      end
    end
  end
end
