# frozen_string_literal: true

module Billing
  class WebhookHandler < ApplicationService
    HANDLERS = {
      "invoice.paid" => Handlers::InvoicePaid,
      "invoice.payment_failed" => Handlers::InvoicePaymentFailed,
      "customer.subscription.updated" => Handlers::SubscriptionUpdated,
      "customer.subscription.deleted" => Handlers::SubscriptionDeleted
    }.freeze

    CHECKOUT_EVENT = "checkout.session.completed"

    def initialize(event_data)
      @event_data = event_data
    end

    private

    attr_reader :event_data

    def run
      return unhandled_event_result unless handler_class

      handler_class.new(event_data).call
    end

    # checkout.session.completed covers two flows: a normal subscription
    # checkout and the one-time Guided Setup payment. They are told apart by
    # the session mode and the guided_setup metadata flag.
    def handler_class
      return checkout_handler if event_type == CHECKOUT_EVENT

      HANDLERS[event_type]
    end

    def checkout_handler
      guided_setup_purchase? ? Handlers::CreditPurchaseCompleted : Handlers::CheckoutCompleted
    end

    def guided_setup_purchase?
      checkout_object[:mode] == "payment" && checkout_object.dig(:metadata, :guided_setup) == "true"
    end

    def checkout_object
      event_data.dig(:data, :object) || {}
    end

    def event_type
      event_data[:type]
    end

    def unhandled_event_result
      success_result(account: nil)
    end
  end
end
