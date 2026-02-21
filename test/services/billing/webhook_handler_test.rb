# frozen_string_literal: true

require "test_helper"

class Billing::WebhookHandlerTest < ActiveSupport::TestCase
  test "dispatches invoice.paid to InvoicePaidHandler" do
    account.update!(stripe_customer_id: "cus_test123")

    result = handler(invoice_paid_event).call

    assert result[:success]
    assert_equal account, result[:account]
  end

  test "dispatches invoice.payment_failed to InvoicePaymentFailedHandler" do
    account.update!(stripe_customer_id: "cus_test123")

    result = handler(invoice_payment_failed_event).call

    assert result[:success]
    assert_equal account, result[:account]
  end

  test "dispatches customer.subscription.updated to SubscriptionUpdatedHandler" do
    account.update!(stripe_customer_id: "cus_test123")

    result = handler(subscription_updated_event).call

    assert result[:success]
    assert_equal account, result[:account]
  end

  test "dispatches customer.subscription.deleted to SubscriptionDeletedHandler" do
    account.update!(stripe_customer_id: "cus_test123")

    result = handler(subscription_deleted_event).call

    assert result[:success]
    assert_equal account, result[:account]
  end

  test "dispatches checkout.session.completed to CheckoutCompletedHandler" do
    account.update!(stripe_customer_id: "cus_test123")

    result = handler(checkout_completed_event).call

    assert result[:success]
    assert_equal account, result[:account]
  end

  test "returns success for unknown event types" do
    result = handler(unknown_event).call

    assert result[:success]
    assert_nil result[:account]
  end

  test "returns error when account not found" do
    result = handler(invoice_paid_event).call

    assert_not result[:success]
    assert_includes result[:errors].first, "Account not found"
  end

  private

  def handler(event_data)
    Billing::WebhookHandler.new(event_data)
  end

  def account
    @account ||= accounts(:one)
  end

  def invoice_paid_event
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

  def invoice_payment_failed_event
    {
      id: "evt_test456",
      type: "invoice.payment_failed",
      data: {
        object: {
          id: "in_test456",
          customer: "cus_test123",
          subscription: "sub_test123",
          status: "open"
        }
      }
    }
  end

  def subscription_updated_event
    {
      id: "evt_test789",
      type: "customer.subscription.updated",
      data: {
        object: {
          id: "sub_test123",
          customer: "cus_test123",
          status: "active",
          current_period_start: Time.current.to_i,
          current_period_end: 30.days.from_now.to_i
        }
      }
    }
  end

  def subscription_deleted_event
    {
      id: "evt_test101",
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

  def checkout_completed_event
    {
      id: "evt_test102",
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

  def unknown_event
    {
      id: "evt_unknown",
      type: "unknown.event.type",
      data: { object: {} }
    }
  end
end
