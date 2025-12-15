# frozen_string_literal: true

module Shopify
  class WebhookHandler
    HANDLERS = {
      Shopify::TOPIC_ORDERS_PAID => Shopify::Handlers::OrderPaid,
      Shopify::TOPIC_CUSTOMERS_CREATE => Shopify::Handlers::CustomerCreated
    }.freeze

    def initialize(account, topic, payload)
      @account = account
      @topic = topic
      @payload = payload
    end

    def call
      handler_class = HANDLERS[topic]
      return { success: true, skipped: true } unless handler_class

      handler_class.new(account, payload).call
    end

    private

    attr_reader :account, :topic, :payload
  end
end
