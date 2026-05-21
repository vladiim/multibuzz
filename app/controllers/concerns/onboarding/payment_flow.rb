# frozen_string_literal: true

# Post-magic-link payment surface: customer is signed in, GuidedSetup has an
# active token (or has just transitioned to in_progress after webhook). Picks
# a plan, hits Stripe Checkout via Billing::CreditCheckoutService, and lands
# on a confirmation once the credit has been granted.
module Onboarding
  module PaymentFlow
    extend ActiveSupport::Concern

    included do
      before_action :skip_if_already_paid, only: %i[payment_setup start_payment]
      before_action :require_active_payment_link, only: %i[payment_setup start_payment]
      before_action :require_payment_context, only: %i[payment_complete]
    end

    def payment_setup
      @plans = Plan.active.paid.sorted
    end

    def start_payment
      return redirect_to(onboarding_payment_setup_path, alert: "Choose a plan to continue.") if plan_slug.blank?

      checkout_result[:success] ?
        redirect_to(checkout_result[:checkout_url], allow_other_host: true) :
        redirect_to(onboarding_payment_setup_path, alert: checkout_result[:errors].first)
    end

    def payment_complete; end

    private

    def skip_if_already_paid
      return unless current_account.guided_setup&.in_progress?

      redirect_to dashboard_path
    end

    def require_active_payment_link
      return if current_account.guided_setup&.payment_token_active?

      redirect_to onboarding_path, alert: "Your payment link has expired. Ask your specialist for a new one."
    end

    # Stripe redirects to success_url synchronously while the webhook arrives
    # asynchronously. payment_complete must therefore accept arrivals before
    # the webhook has fired -- we render the processing state and let the
    # Turbo broadcast from CreditPurchaseCompleted swap it for the success
    # state once the credit lands. We only redirect away if there is no
    # payment context at all (random URL hit while signed in).
    def require_payment_context
      return if current_account.guided_setup&.kickoff_booked_at.present?

      redirect_to onboarding_path
    end

    def plan_slug
      params[:plan_slug].to_s.presence
    end

    def checkout_result
      @checkout_result ||= Billing::CreditCheckoutService.new(
        account: current_account,
        plan_slug: plan_slug,
        urls: { success: onboarding_payment_complete_url, cancel: onboarding_payment_setup_url }
      ).call
    end
  end
end
