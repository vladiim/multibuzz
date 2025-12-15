# frozen_string_literal: true

module Webhooks
  class ShopifyController < ApplicationController
    skip_forgery_protection

    def create
      return render_error(Shopify::ERROR_UNKNOWN_SHOP, :unauthorized) unless account
      return render_error(Shopify::ERROR_INVALID_SIGNATURE, :unauthorized) unless valid_signature?
      return render_warning(Shopify::WARNING_NO_VISITOR) unless visitor_id.present?
      return render_success if already_processed?

      Shopify::WebhookHandler.new(account, topic, payload).call
      render_success
    end

    private

    def valid_signature?
      Shopify::WebhookVerifier.new(
        payload: request.raw_post,
        signature: hmac_header,
        secret: account&.shopify_webhook_secret
      ).valid?
    end

    def account
      @account ||= Account.find_by(shopify_domain: shop_domain_header)
    end

    def payload
      @payload ||= JSON.parse(request.raw_post).deep_symbolize_keys
    end

    def visitor_id
      @visitor_id ||= extract_note_attribute(Shopify::NOTE_ATTR_VISITOR_ID)
    end

    def extract_note_attribute(name)
      note_attributes = payload[:note_attributes] || []
      note_attributes.find { |attr| attr[:name] == name }&.dig(:value)
    end

    def already_processed?
      order_id = payload[:id]
      return false unless order_id.present?

      account.conversions
        .where("properties->>? = ?", Shopify::PROP_ORDER_ID, order_id.to_s)
        .exists?
    end

    def topic
      request.headers[Shopify::HEADER_TOPIC]
    end

    def hmac_header
      request.headers[Shopify::HEADER_HMAC]
    end

    def shop_domain_header
      request.headers[Shopify::HEADER_SHOP_DOMAIN]
    end

    def render_error(message, status)
      render json: { error: message }, status: status
    end

    def render_warning(message)
      render json: { received: true, warning: message }
    end

    def render_success
      render json: { received: true }
    end
  end
end
