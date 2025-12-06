# frozen_string_literal: true

module Billing
  class ReportUsageService < ApplicationService
    def initialize(account)
      @account = account
    end

    private

    attr_reader :account

    def run
      return skip_result("No active subscription") unless has_active_subscription?
      return skip_result("No usage to report") unless has_usage_to_report?

      report_to_stripe
      build_success_result
    end

    # --- Checks ---

    def has_active_subscription?
      account.stripe_subscription_id.present?
    end

    def has_usage_to_report?
      current_usage.positive?
    end

    # --- Stripe Integration ---

    def report_to_stripe
      # TODO: Integrate with Stripe Meters API when ready
      # Stripe::Billing::MeterEvent.create(
      #   event_name: "events_processed",
      #   payload: {
      #     value: current_usage,
      #     stripe_customer_id: account.stripe_customer_id
      #   }
      # )
    end

    # --- Results ---

    def build_success_result
      success_result(
        usage_reported: current_usage,
        overage_events: overage_events,
        plan_limit: plan_limit
      )
    end

    def skip_result(reason)
      { skipped: true, reason: reason }
    end

    # --- Usage Calculations ---

    def current_usage
      @current_usage ||= usage_counter.current_usage
    end

    def plan_limit
      @plan_limit ||= usage_counter.event_limit
    end

    def overage_events
      [current_usage - plan_limit, 0].max
    end

    def usage_counter
      @usage_counter ||= UsageCounter.new(account)
    end
  end
end
