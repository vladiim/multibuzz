# frozen_string_literal: true

module Accounts
  class BillingController < BaseController
    include RequireAdmin
    skip_marketing_analytics

    def show
      @plans = Plan.active.paid.sorted
    end

    def checkout
      checkout_result[:success] ? redirect_to_checkout : redirect_with_error(checkout_result[:errors].first)
    end

    def portal
      portal_result[:success] ? redirect_to_portal : redirect_with_error(portal_result[:errors].first)
    end

    def success
      @session_id = params[:session_id]
    end

    def cancel
      redirect_to account_billing_path, notice: t(".cancelled")
    end

    private

    def checkout_result
      @checkout_result ||= Billing::CheckoutService.new(
        account: current_account,
        plan_slug: params[:plan_slug],
        user: current_user,
        success_url: success_account_billing_url(session_id: "{CHECKOUT_SESSION_ID}"),
        cancel_url: cancel_account_billing_url
      ).call
    end

    def portal_result
      @portal_result ||= Billing::PortalService.new(
        account: current_account,
        return_url: account_billing_url
      ).call
    end

    def redirect_to_checkout
      redirect_to checkout_result[:checkout_url], allow_other_host: true
    end

    def redirect_to_portal
      redirect_to portal_result[:portal_url], allow_other_host: true
    end

    def redirect_with_error(message)
      redirect_to account_billing_path, alert: message
    end
  end
end
