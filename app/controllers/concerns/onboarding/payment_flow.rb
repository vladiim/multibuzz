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
      before_action :require_kickoff_booked, only: %i[payment_setup start_payment]
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

    def payment_complete
      verify_checkout_session_if_present
    end

    private

    def skip_if_already_paid
      return unless current_account.guided_setup&.in_progress?

      redirect_to dashboard_path
    end

    # Any signed-in customer who has booked the kickoff can pay -- the
    # magic-link token is a convenience for getting them onto this page in
    # one click from outside the app, never a gate.
    def require_kickoff_booked
      return if current_account.guided_setup&.kickoff_booked_at.present?

      redirect_to onboarding_path
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

    # Stripe's webhook is canonical but it races the success_url redirect
    # and doesn't fire at all in local dev without the Stripe CLI. We
    # verify the session ourselves on landing so the customer isn't stuck
    # on the processing state. The handler the verifier delegates to is
    # idempotent -- if the webhook also lands, it no-ops.
    def verify_checkout_session_if_present
      return if params[:session_id].blank?
      return if current_account.guided_setup&.in_progress?

      Billing::VerifyCheckoutSessionService.new(
        session_id: params[:session_id],
        account: current_account
      ).call
      current_account.guided_setup&.reload
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
