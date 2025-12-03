require "ostruct"

module Billing
  class CheckoutService < ApplicationService
    def initialize(account:, plan_slug:, user:, success_url:, cancel_url:, stripe_client: nil)
      @account = account
      @plan_slug = plan_slug
      @user = user
      @success_url = success_url
      @cancel_url = cancel_url
      @stripe_client = stripe_client || DefaultStripeClient.new
    end

    private

    attr_reader :account, :plan_slug, :user, :success_url, :cancel_url, :stripe_client

    def run
      return validation_error if invalid?

      ensure_stripe_customer
      create_checkout_session
    end

    def invalid?
      !plan || plan.free? || plan.stripe_price_id.blank?
    end

    def validation_error
      return error_result(["Plan not found"]) unless plan
      return error_result(["Cannot checkout free plan"]) if plan.free?

      error_result(["Plan not configured for billing"])
    end

    def ensure_stripe_customer
      return if account.stripe_customer_id.present?

      account.update!(stripe_customer_id: new_customer.id)
    end

    def create_checkout_session
      success_result(
        session_id: checkout_session.id,
        checkout_url: checkout_session.url
      )
    rescue Stripe::StripeError => e
      error_result(["Stripe error: #{e.message}"])
    end

    def new_customer
      @new_customer ||= stripe_client.create_customer(
        email: billing_email,
        metadata: { account_id: account.prefix_id }
      )
    end

    def checkout_session
      @checkout_session ||= stripe_client.create_checkout_session(session_params)
    end

    def session_params
      {
        customer: account.stripe_customer_id,
        mode: "subscription",
        line_items: line_items,
        success_url: success_url,
        cancel_url: cancel_url,
        metadata: session_metadata
      }
    end

    def line_items
      # Don't pass quantity for metered prices
      [{ price: plan.stripe_price_id }]
    end

    def session_metadata
      {
        account_id: account.prefix_id,
        plan_slug: plan.slug
      }
    end

    def billing_email
      account.billing_email || user.email
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
