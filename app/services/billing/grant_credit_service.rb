# frozen_string_literal: true

module Billing
  # Grants Guided Setup credit. The credit is a non-refundable Stripe customer
  # balance credit: it only ever draws down against the account's future
  # invoices and is never paid out as cash. An AccountCredit ledger row records
  # the grant -- there is deliberately no path that converts it back to money.
  class GrantCreditService < ApplicationService
    CREDIT_SOURCE = "guided_setup"

    def initialize(account:, plan:, stripe_client: nil)
      @account = account
      @plan = plan
      @stripe_client = stripe_client || DefaultStripeClient.new
    end

    private

    attr_reader :account, :plan, :stripe_client

    def run
      return error_result([ "Account has no Stripe customer" ]) unless account.has_stripe_customer?

      success_result(account_credit: granted_credit)
    rescue Stripe::StripeError => e
      error_result([ "Stripe error: #{e.message}" ])
    end

    def granted_credit
      account.account_credits.create!(
        applied_plan: plan,
        amount_cents: amount_cents,
        source: CREDIT_SOURCE,
        granted_at: Time.current,
        stripe_balance_transaction_id: balance_transaction.id
      )
    end

    def balance_transaction
      @balance_transaction ||= stripe_client.credit_customer_balance(
        customer_id: account.stripe_customer_id,
        amount_cents: amount_cents
      )
    end

    def amount_cents
      ::Billing::GUIDED_SETUP_CREDIT_CENTS
    end

    class DefaultStripeClient
      # A negative balance transaction is invoice credit, not a refundable
      # charge -- Stripe only ever consumes it against future invoices.
      def credit_customer_balance(customer_id:, amount_cents:)
        Stripe::Customer.create_balance_transaction(
          customer_id,
          amount: -amount_cents,
          currency: "usd",
          description: "mbuzz Guided Setup credit"
        )
      end
    end
  end
end
