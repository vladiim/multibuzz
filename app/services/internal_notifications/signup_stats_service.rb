# frozen_string_literal: true

module InternalNotifications
  class SignupStatsService
    COHORT_DAYS = 30
    PAID_BILLING_STATUSES = %i[active past_due].freeze

    def call
      {
        total_accounts: total_accounts,
        signups_today: signups_today,
        signups_this_week: signups_this_week,
        signups_this_month: signups_this_month,
        trial_to_paid_rate_30d: trial_to_paid_rate_30d
      }
    end

    private

    def total_accounts = Account.count
    def signups_today = Account.where("created_at >= ?", 1.day.ago).count
    def signups_this_week = Account.where("created_at >= ?", 1.week.ago).count
    def signups_this_month = Account.where("created_at >= ?", 1.month.ago).count

    def trial_to_paid_rate_30d
      return 0 if cohort_size.zero?

      ((paid_in_cohort.to_f / cohort_size) * 100).round
    end

    def cohort_size = @cohort_size ||= Account.where(created_at: cohort_window).count
    def paid_in_cohort = Account.where(created_at: cohort_window, billing_status: PAID_BILLING_STATUSES).count
    def cohort_window = COHORT_DAYS.days.ago..Time.current
  end
end
