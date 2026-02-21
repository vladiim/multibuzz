# frozen_string_literal: true

module Billing
  class PortalService < ApplicationService
    def initialize(account:, return_url:, stripe_client: nil)
      @account = account
      @return_url = return_url
      @stripe_client = stripe_client || DefaultStripeClient.new
    end

    private

    attr_reader :account, :return_url, :stripe_client

    def run
      return error_result([ "No billing account found" ]) if invalid?

      create_portal_session
    end

    def invalid?
      account.stripe_customer_id.blank?
    end

    def create_portal_session
      success_result(portal_url: portal_session.url)
    rescue Stripe::StripeError => e
      error_result([ "Stripe error: #{e.message}" ])
    end

    def portal_session
      @portal_session ||= stripe_client.create_portal_session(session_params)
    end

    def session_params
      {
        customer: account.stripe_customer_id,
        return_url: return_url
      }
    end

    class DefaultStripeClient
      def create_portal_session(params)
        Stripe::BillingPortal::Session.create(params)
      end
    end
  end
end
