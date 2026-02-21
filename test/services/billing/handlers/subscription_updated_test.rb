# frozen_string_literal: true

require "test_helper"

module Billing
  module Handlers
    class SubscriptionUpdatedTest < ActiveSupport::TestCase
      test "syncs subscription details from stripe event" do
        account.update!(
          stripe_customer_id: "cus_test123",
          billing_status: :trialing
        )

        period_start_ts = Time.current.to_i
        period_end_ts = 30.days.from_now.to_i

        event_data = build_event_data(
          status: "active",
          current_period_start: period_start_ts,
          current_period_end: period_end_ts
        )

        result = handler(event_data).call

        assert result[:success]

        account.reload

        assert_predicate account, :billing_active?
        assert_equal "sub_test123", account.stripe_subscription_id
        assert_in_delta Time.zone.at(period_start_ts), account.current_period_start, 1.second
        assert_in_delta Time.zone.at(period_end_ts), account.current_period_end, 1.second
      end

      test "maps stripe trialing status to trialing" do
        account.update!(
          stripe_customer_id: "cus_test123",
          billing_status: :active
        )

        event_data = build_event_data(status: "trialing")

        result = handler(event_data).call

        assert result[:success]
        assert_predicate account.reload, :billing_trialing?
      end

      test "maps stripe past_due status to past_due" do
        account.update!(
          stripe_customer_id: "cus_test123",
          billing_status: :active
        )

        event_data = build_event_data(status: "past_due")

        result = handler(event_data).call

        assert result[:success]
        assert_predicate account.reload, :billing_past_due?
      end

      test "maps stripe canceled status to cancelled" do
        account.update!(
          stripe_customer_id: "cus_test123",
          billing_status: :active
        )

        event_data = build_event_data(status: "canceled")

        result = handler(event_data).call

        assert result[:success]
        assert_predicate account.reload, :billing_cancelled?
      end

      test "keeps current status for unknown stripe status" do
        account.update!(
          stripe_customer_id: "cus_test123",
          billing_status: :active
        )

        event_data = build_event_data(status: "unknown_status")

        result = handler(event_data).call

        assert result[:success]
        assert_predicate account.reload, :billing_active?
      end

      test "returns error when account not found" do
        event_data = build_event_data(status: "active")

        result = handler(event_data).call

        assert_not result[:success]
        assert_includes result[:errors].first, "Account not found"
      end

      private

      def handler(event_data)
        Billing::Handlers::SubscriptionUpdated.new(event_data)
      end

      def account
        @account ||= accounts(:one)
      end

      def build_event_data(status:, current_period_start: Time.current.to_i, current_period_end: 30.days.from_now.to_i)
        {
          id: "evt_test123",
          type: "customer.subscription.updated",
          data: {
            object: {
              id: "sub_test123",
              customer: "cus_test123",
              status: status,
              current_period_start: current_period_start,
              current_period_end: current_period_end
            }
          }
        }
      end
    end
  end
end
