# frozen_string_literal: true

require "csv"

module Admin
  class CustomerMetricsCsv
    HEADERS = [
      "Account", "Account ID", "Plan", "Billing status", "Sign up date",
      "LTV", "MRR", "Has test records", "Total prod records", "Avg monthly records",
      "User count", "User login count", "Avg monthly logins", "Active subscription months",
      "Churn date", "Days to activation", "Days to first payment", "Onboarding %",
      "Last login at", "Last event at", "Connected integrations"
    ].freeze

    def initialize(rows)
      @rows = rows
    end

    def generate
      CSV.generate do |csv|
        csv << HEADERS
        rows.each { |row| csv << csv_line(row) }
      end
    end

    private

    attr_reader :rows

    def csv_line(row)
      identity_columns(row) + billing_columns(row) + usage_columns(row) + milestone_columns(row) + activity_columns(row)
    end

    def identity_columns(row)
      [ row.name, row.prefix_id, row.plan_name, row.billing_status, row.signed_up_at&.to_date ]
    end

    def billing_columns(row)
      [ format_dollars(row.lifetime_value_cents), format_dollars(row.mrr_cents) ]
    end

    def usage_columns(row)
      [ row.has_test_records, row.total_prod_records, row.avg_monthly_records, row.user_count, row.user_login_count, row.avg_monthly_logins ]
    end

    def milestone_columns(row)
      [ row.active_subscription_months, row.churn_date&.to_date, row.days_to_activation, row.days_to_first_payment, row.onboarding_percentage ]
    end

    def activity_columns(row)
      [ row.last_login_at, row.last_event_at, row.connected_integrations ]
    end

    def format_dollars(cents)
      "$%0.2f" % (cents.to_f / ::Billing::CENTS_PER_DOLLAR)
    end
  end
end
