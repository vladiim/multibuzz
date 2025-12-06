module Admin
  class BillingController < BaseController
    def show
      @metrics = billing_metrics
      @accounts = Account.includes(:plan).order(created_at: :desc)
    end

    private

    def billing_metrics
      Billing::MetricsService.new.call
    end
  end
end
