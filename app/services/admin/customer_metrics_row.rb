# frozen_string_literal: true

module Admin
  CustomerMetricsRow = Data.define(
    :id,
    :prefix_id,
    :name,
    :plan_name,
    :billing_status,
    :signed_up_at,
    :lifetime_value_cents,
    :mrr_cents,
    :has_test_records,
    :total_prod_records,
    :avg_monthly_records,
    :user_count,
    :user_login_count,
    :avg_monthly_logins,
    :active_subscription_months,
    :churn_date,
    :days_to_activation,
    :days_to_first_payment,
    :onboarding_percentage,
    :last_login_at,
    :last_event_at,
    :connected_integrations
  )
end
