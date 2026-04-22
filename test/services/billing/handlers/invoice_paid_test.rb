# frozen_string_literal: true

require "test_helper"

module Billing
  module Handlers
    class InvoicePaidTest < ActiveSupport::TestCase
      test "clears past_due status when account is past_due" do
        account.update!(
          stripe_customer_id: "cus_test123",
          billing_status: :past_due,
          payment_failed_at: 1.day.ago,
          grace_period_ends_at: 2.days.from_now
        )

        result = handler(valid_event_data).call

        assert result[:success]

        account.reload

        assert_predicate account, :billing_active?
        assert_nil account.payment_failed_at
        assert_nil account.grace_period_ends_at
      end

      test "does not change status when account is already active" do
        account.update!(
          stripe_customer_id: "cus_test123",
          billing_status: :active
        )

        result = handler(valid_event_data).call

        assert result[:success]
        assert_predicate account.reload, :billing_active?
      end

      test "unlocks events when locked events exist" do
        account.update!(
          stripe_customer_id: "cus_test123",
          billing_status: :past_due
        )

        # Create a locked event
        locked_event = account.events.create!(
          event_type: "page_view",
          visitor: visitors(:one),
          session: sessions(:one),
          occurred_at: Time.current,
          properties: { url: "https://example.com" },
          locked: true
        )

        result = handler(valid_event_data).call

        assert result[:success]
        assert_not locked_event.reload.locked?
      end

      test "returns error when account not found" do
        # Don't set stripe_customer_id

        result = handler(valid_event_data).call

        assert_not result[:success]
        assert_includes result[:errors].first, "Account not found"
      end

      test "increments lifetime_value_cents by amount_paid" do
        account.update!(stripe_customer_id: "cus_test123", lifetime_value_cents: 4000)

        handler(paid_event_with_amount(2900)).call

        assert_equal 6900, account.reload.lifetime_value_cents
      end

      test "treats missing amount_paid as zero" do
        account.update!(stripe_customer_id: "cus_test123", lifetime_value_cents: 1000)

        handler(valid_event_data).call

        assert_equal 1000, account.reload.lifetime_value_cents
      end

      private

      def paid_event_with_amount(cents)
        valid_event_data.deep_merge(data: { object: { amount_paid: cents } })
      end

      def handler(event_data)
        Billing::Handlers::InvoicePaid.new(event_data)
      end

      def account
        @account ||= accounts(:one)
      end

      def valid_event_data
        {
          id: "evt_test123",
          type: "invoice.paid",
          data: {
            object: {
              id: "in_test123",
              customer: "cus_test123",
              subscription: "sub_test123",
              status: "paid"
            }
          }
        }
      end
    end
  end
end
