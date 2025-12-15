# frozen_string_literal: true

module Shopify
  # --- HTTP Headers ---
  HEADER_HMAC = "X-Shopify-Hmac-SHA256"
  HEADER_TOPIC = "X-Shopify-Topic"
  HEADER_SHOP_DOMAIN = "X-Shopify-Shop-Domain"

  # --- Webhook Topics ---
  TOPIC_ORDERS_PAID = "orders/paid"
  TOPIC_CUSTOMERS_CREATE = "customers/create"

  SUPPORTED_TOPICS = [
    TOPIC_ORDERS_PAID,
    TOPIC_CUSTOMERS_CREATE
  ].freeze

  # --- Cart Note Attributes ---
  NOTE_ATTR_VISITOR_ID = "_mbuzz_visitor_id"
  NOTE_ATTR_SESSION_ID = "_mbuzz_session_id"

  # --- Conversion Properties ---
  PROP_ORDER_ID = "shopify_order_id"
  PROP_ORDER_NUMBER = "shopify_order_number"
  PROP_CUSTOMER_EMAIL = "customer_email"

  # --- Conversion Types ---
  CONVERSION_TYPE_PURCHASE = "purchase"
  CONVERSION_TYPE_SIGNUP = "signup"

  # --- Error Messages ---
  ERROR_INVALID_SIGNATURE = "Invalid signature"
  ERROR_UNKNOWN_SHOP = "Unknown shop"
  WARNING_NO_VISITOR = "No visitor_id found"
end
