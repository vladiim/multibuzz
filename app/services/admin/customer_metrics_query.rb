# frozen_string_literal: true

module Admin
  class CustomerMetricsQuery
    PAID_BILLING_STATUSES = %w[trialing active].freeze
    DAYS_PER_MONTH = 30.0
    PAID_INVOICE_EVENT_TYPE = "invoice.payment_succeeded"

    def call
      accounts.map { |account| build_row(account) }
    end

    private

    def accounts
      @accounts ||= Account.includes(:plan).order(created_at: :desc).to_a
    end

    def build_row(account)
      CustomerMetricsRow.new(**identity_fields(account), **billing_fields(account), **usage_fields(account), **milestone_fields(account), **activity_fields(account))
    end

    def identity_fields(account)
      { id: account.id, prefix_id: account.prefix_id, name: account.name, signed_up_at: account.created_at }
    end

    def billing_fields(account)
      {
        plan_name: account.plan&.name || "Free",
        billing_status: account.billing_status,
        lifetime_value_cents: account.lifetime_value_cents,
        mrr_cents: mrr_for(account),
        active_subscription_months: months_active(account),
        churn_date: account.subscription_cancelled_at
      }
    end

    def usage_fields(account)
      {
        has_test_records: test_event_account_ids.include?(account.id),
        total_prod_records: prod_record_count(account),
        avg_monthly_records: round_per_month(prod_record_count(account), account),
        user_count: user_counts.fetch(account.id, 0),
        user_login_count: login_count(account),
        avg_monthly_logins: round_per_month(login_count(account), account)
      }
    end

    def prod_record_count(account) = prod_event_counts.fetch(account.id, 0)
    def login_count(account) = login_counts.fetch(account.id, 0)

    def milestone_fields(account)
      {
        days_to_activation: days_between(account.created_at, account.activated_at),
        days_to_first_payment: days_between(account.created_at, first_payment_at.fetch(account.id, nil)),
        onboarding_percentage: account.onboarding_percentage
      }
    end

    def activity_fields(account)
      {
        last_login_at: last_login_at.fetch(account.id, nil),
        last_event_at: last_event_at.fetch(account.id, nil),
        connected_integrations: integration_counts.fetch(account.id, 0)
      }
    end

    def mrr_for(account)
      return 0 unless PAID_BILLING_STATUSES.include?(account.billing_status)

      account.plan&.monthly_price_cents.to_i
    end

    def round_per_month(total, account)
      (total.to_f / months_since(account.created_at)).round
    end

    def months_since(timestamp)
      [ (Time.current - timestamp) / (DAYS_PER_MONTH.days), 1.0 ].max
    end

    def months_active(account)
      return nil unless account.subscription_started_at

      ends_at = account.subscription_cancelled_at || Time.current
      ((ends_at - account.subscription_started_at) / (DAYS_PER_MONTH.days)).round
    end

    def days_between(start_at, end_at)
      return nil unless start_at && end_at

      ((end_at - start_at) / 1.day).round
    end

    def account_ids
      @account_ids ||= accounts.map(&:id)
    end

    def prod_event_counts
      @prod_event_counts ||= Event.where(account_id: account_ids, is_test: false).group(:account_id).count
    end

    def test_event_account_ids
      @test_event_account_ids ||= Event.where(account_id: account_ids, is_test: true).distinct.pluck(:account_id).to_set
    end

    def last_event_at
      @last_event_at ||= Event.where(account_id: account_ids).group(:account_id).maximum(:occurred_at)
    end

    def user_counts
      @user_counts ||= AccountMembership.accepted.where(account_id: account_ids).group(:account_id).count
    end

    def login_counts
      @login_counts ||= aggregate_user_metric(:sign_in_count) { |scope| scope.sum(:sign_in_count) }
    end

    def last_login_at
      @last_login_at ||= aggregate_user_metric(:last_sign_in_at) { |scope| scope.maximum(:last_sign_in_at) }
    end

    def aggregate_user_metric(_column)
      yield AccountMembership.accepted.where(account_id: account_ids).joins(:user).group(:account_id)
    end

    def integration_counts
      @integration_counts ||= AdPlatformConnection.where(account_id: account_ids).group(:account_id).count
    end

    def first_payment_at
      @first_payment_at ||= BillingEvent
        .where(account_id: account_ids, event_type: PAID_INVOICE_EVENT_TYPE)
        .group(:account_id).minimum(:created_at)
    end
  end
end
