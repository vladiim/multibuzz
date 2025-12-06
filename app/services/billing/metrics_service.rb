module Billing
  class MetricsService < ApplicationService
    PAYING_STATUSES = %i[active past_due].freeze

    private

    def run
      success_result(
        mrr_cents: mrr_cents,
        mrr: mrr_cents.to_f / ::Billing::CENTS_PER_DOLLAR,
        account_counts: account_counts,
        mrr_by_plan: mrr_by_plan,
        total_accounts: total_accounts
      )
    end

    def mrr_cents
      @mrr_cents ||= paying_accounts
        .joins(:plan)
        .sum("plans.monthly_price_cents")
    end

    def account_counts
      @account_counts ||= Account
        .group(:billing_status)
        .count
        .transform_keys(&:to_sym)
    end

    def mrr_by_plan
      @mrr_by_plan ||= paying_accounts
        .joins(:plan)
        .group("plans.id")
        .sum("plans.monthly_price_cents")
    end

    def total_accounts
      @total_accounts ||= Account.count
    end

    def paying_accounts
      Account.where(billing_status: PAYING_STATUSES)
    end
  end
end
