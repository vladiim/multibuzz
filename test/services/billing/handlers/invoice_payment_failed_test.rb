# frozen_string_literal: true

require "test_helper"

module Billing
  module Handlers
    class InvoicePaymentFailedTest < ActiveSupport::TestCase
      test "marks account as past_due when active" do
        account.update!(
          stripe_customer_id: "cus_test123",
          billing_status: :active
        )

        freeze_time do
          result = handler(valid_event_data).call

          assert result[:success]

          account.reload

          assert_predicate account, :billing_past_due?
          assert_equal Time.current, account.payment_failed_at
          assert_equal Billing::GRACE_PERIOD_DAYS.days.from_now, account.grace_period_ends_at
        end
      end

      test "does not update when already past_due" do
        original_payment_failed_at = 2.days.ago
        account.update!(
          stripe_customer_id: "cus_test123",
          billing_status: :past_due,
          payment_failed_at: original_payment_failed_at,
          grace_period_ends_at: 1.day.from_now
        )

        result = handler(valid_event_data).call

        assert result[:success]

        account.reload
        # payment_failed_at should not be updated
        assert_in_delta original_payment_failed_at, account.payment_failed_at, 1.second
      end

      test "returns error when account not found" do
        result = handler(valid_event_data).call

        assert_not result[:success]
        assert_includes result[:errors].first, "Account not found"
      end

      private

      def handler(event_data)
        Billing::Handlers::InvoicePaymentFailed.new(event_data)
      end

      def account
        @account ||= accounts(:one)
      end

      def valid_event_data
        {
          id: "evt_test123",
          type: "invoice.payment_failed",
          data: {
            object: {
              id: "in_test123",
              customer: "cus_test123",
              subscription: "sub_test123",
              status: "open"
            }
          }
        }
      end
    end
  end
end
