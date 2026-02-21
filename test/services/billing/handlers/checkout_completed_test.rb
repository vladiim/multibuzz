# frozen_string_literal: true

require "test_helper"

module Billing
  module Handlers
    class CheckoutCompletedTest < ActiveSupport::TestCase
      test "activates subscription with valid plan" do
        account.update!(stripe_customer_id: "cus_test123")

        result = handler(valid_event_data).call

        assert result[:success]
        assert_equal account, result[:account]

        account.reload

        assert_predicate account, :billing_active?
        assert_equal "sub_new123", account.stripe_subscription_id
        assert_equal starter_plan, account.plan
        assert_predicate account.subscription_started_at, :present?
      end

      test "returns error when plan not found" do
        account.update!(stripe_customer_id: "cus_test123")

        result = handler(event_data_with_invalid_plan).call

        assert_not result[:success]
        assert_includes result[:errors].first, "Plan not found"

        # Account should not be modified
        account.reload

        assert_nil account.stripe_subscription_id
        assert_nil account.plan
      end

      test "returns error when plan_slug missing from metadata" do
        account.update!(stripe_customer_id: "cus_test123")

        result = handler(event_data_without_plan_slug).call

        assert_not result[:success]
        assert_includes result[:errors].first, "Plan not found"
      end

      test "returns error when account not found" do
        # Don't set stripe_customer_id on account

        result = handler(valid_event_data).call

        assert_not result[:success]
        assert_includes result[:errors].first, "Account not found"
      end

      test "overwrites existing billing status" do
        account.update!(
          stripe_customer_id: "cus_test123",
          billing_status: :trialing
        )

        result = handler(valid_event_data).call

        assert result[:success]
        assert_predicate account.reload, :billing_active?
      end

      private

      def handler(event_data)
        Billing::Handlers::CheckoutCompleted.new(event_data)
      end

      def account
        @account ||= accounts(:one)
      end

      def starter_plan
        @starter_plan ||= plans(:starter)
      end

      def valid_event_data
        {
          id: "evt_test123",
          type: "checkout.session.completed",
          data: {
            object: {
              id: "cs_test123",
              customer: "cus_test123",
              subscription: "sub_new123",
              metadata: {
                account_id: account.prefix_id,
                plan_slug: "starter"
              }
            }
          }
        }
      end

      def event_data_with_invalid_plan
        valid_event_data.deep_merge(
          data: {
            object: {
              metadata: {
                plan_slug: "nonexistent_plan"
              }
            }
          }
        )
      end

      def event_data_without_plan_slug
        data = valid_event_data.deep_dup
        data[:data][:object][:metadata].delete(:plan_slug)
        data
      end
    end
  end
end
