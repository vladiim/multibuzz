module Billing
  class WebhookHandler < ApplicationService
    HANDLERS = {
      "invoice.paid" => Handlers::InvoicePaid,
      "invoice.payment_failed" => Handlers::InvoicePaymentFailed,
      "customer.subscription.updated" => Handlers::SubscriptionUpdated,
      "customer.subscription.deleted" => Handlers::SubscriptionDeleted,
      "checkout.session.completed" => Handlers::CheckoutCompleted
    }.freeze

    def initialize(event_data)
      @event_data = event_data
    end

    private

    attr_reader :event_data

    def run
      return unhandled_event_result unless handler_class

      handler_class.new(event_data).call
    end

    def handler_class
      HANDLERS[event_type]
    end

    def event_type
      event_data[:type]
    end

    def unhandled_event_result
      success_result(account: nil)
    end
  end
end
