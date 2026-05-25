# frozen_string_literal: true

# Lands the customer after they click an admin-generated payment link. The
# token alone is enough to authenticate them for this single hop -- we
# validate it, sign in the account's owner, and hand them off to the
# logged-in payment_setup page. The token stays valid until they pay (the
# CreditPurchaseCompleted webhook clears it), so they can re-click if they
# bounce mid-Stripe-checkout.
module Onboarding
  class PaymentLinksController < ApplicationController
    skip_marketing_analytics

    def show
      return redirect_with_alert("This payment link is invalid or has expired.") unless guided_setup
      return redirect_with_alert("This account has no owner to sign in.") unless owner_user

      session[:user_id] = owner_user.id
      redirect_to onboarding_payment_setup_path
    end

    private

    def guided_setup
      @guided_setup ||= GuidedSetup.find_by_active_payment_token(params[:token])
    end

    def owner_user
      @owner_user ||= guided_setup&.account&.owner_user
    end

    def redirect_with_alert(message)
      redirect_to login_path, alert: message
    end
  end
end
