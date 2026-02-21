# frozen_string_literal: true

require "test_helper"

module Billing
  module Handlers
    class SubscriptionDeletedTest < ActiveSupport::TestCase
      test "cancels subscription and clears stripe subscription id" do
        account.update!(
          stripe_customer_id: "cus_test123",
          stripe_subscription_id: "sub_old123",
          billing_status: :active
        )

        result = handler(valid_event_data).call

        assert result[:success]

        account.reload

        assert_predicate account, :billing_cancelled?
        assert_nil account.stripe_subscription_id
      end

      test "cancels already past_due subscription" do
        account.update!(
          stripe_customer_id: "cus_test123",
          stripe_subscription_id: "sub_old123",
          billing_status: :past_due
        )

        result = handler(valid_event_data).call

        assert result[:success]
        assert_predicate account.reload, :billing_cancelled?
      end

      test "returns error when account not found" do
        result = handler(valid_event_data).call

        assert_not result[:success]
        assert_includes result[:errors].first, "Account not found"
      end

      private

      def handler(event_data)
        Billing::Handlers::SubscriptionDeleted.new(event_data)
      end

      def account
        @account ||= accounts(:one)
      end

      def valid_event_data
        {
          id: "evt_test123",
          type: "customer.subscription.deleted",
          data: {
            object: {
              id: "sub_test123",
              customer: "cus_test123",
              status: "canceled"
            }
          }
        }
      end
    end
  end
end
