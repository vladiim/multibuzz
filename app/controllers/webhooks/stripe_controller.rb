# frozen_string_literal: true

module Webhooks
  class StripeController < ApplicationController
    skip_forgery_protection

    class_attribute :webhook_secret_override

    def create
      return render_signature_error unless valid_signature?
      return render_success if already_processed?

      process_event
      render_success
    end

    private

    def valid_signature?
      return false unless stripe_signature.present?

      Stripe::Webhook::Signature.verify_header(
        request.raw_post,
        stripe_signature,
        webhook_secret,
        tolerance: Stripe::Webhook::DEFAULT_TOLERANCE
      )
      true
    rescue Stripe::SignatureVerificationError
      false
    end

    def already_processed?
      BillingEvent.exists?(stripe_event_id: event_id)
    end

    def process_event
      handler_result = Billing::WebhookHandler.new(event_data).call

      BillingEvent.create!(
        account: handler_result[:account],
        stripe_event_id: event_id,
        event_type: event_type,
        processed_at: Time.current,
        payload: event_data
      )
    end

    def event_data
      @event_data ||= JSON.parse(request.raw_post).deep_symbolize_keys
    end

    def event_id
      event_data[:id]
    end

    def event_type
      event_data[:type]
    end

    def stripe_signature
      request.headers["Stripe-Signature"]
    end

    def webhook_secret
      self.class.webhook_secret_override || Rails.application.credentials.dig(:stripe, :webhook_secret)
    end

    def render_signature_error
      render json: { error: "Invalid signature" }, status: :bad_request
    end

    def render_success
      render json: { received: true }
    end
  end
end
