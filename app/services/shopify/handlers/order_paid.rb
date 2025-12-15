# frozen_string_literal: true

module Shopify
  module Handlers
    class OrderPaid < Base
      def call
        return { success: false, error: "Visitor not found" } unless visitor

        conversion = create_conversion
        { success: true, conversion_id: conversion.prefix_id }
      end

      private

      def create_conversion
        Conversion.create!(
          account: account,
          visitor_id: visitor.id,
          session_id: latest_session&.id,
          conversion_type: Shopify::CONVERSION_TYPE_PURCHASE,
          revenue: total_price,
          currency: currency,
          converted_at: Time.current,
          properties: conversion_properties
        )
      end

      def conversion_properties
        {
          Shopify::PROP_ORDER_ID => order_id.to_s,
          Shopify::PROP_ORDER_NUMBER => order_number,
          Shopify::PROP_CUSTOMER_EMAIL => customer_email
        }.compact
      end

      def order_id
        payload[:id]
      end

      def order_number
        payload[:order_number]
      end

      def total_price
        payload[:total_price]&.to_f
      end

      def currency
        payload[:currency] || "USD"
      end

      def customer_email
        payload.dig(:customer, :email)
      end
    end
  end
end
