# frozen_string_literal: true

require "test_helper"
require "ostruct"

class Billing::CreditCheckoutServiceTest < ActiveSupport::TestCase
  test "returns an error when the plan is not found" do
    result = service(plan_slug: "nonexistent").call

    assert_not result[:success]
    assert_includes result[:errors], "Plan not found"
  end

  test "returns an error for the free plan" do
    result = service(plan_slug: "free").call

    assert_not result[:success]
    assert_includes result[:errors], "Cannot checkout free plan"
  end

  test "returns an error when the plan has no Stripe price" do
    plan.update!(stripe_price_id: nil)

    result = service.call

    assert_not result[:success]
    assert_includes result[:errors], "Plan not configured for billing"
  end

  test "creates a Stripe customer when the account has none" do
    account.update!(stripe_customer_id: nil)

    result = service(stripe_client: mock_stripe_client).call

    assert result[:success]
    assert_equal "cus_mock123", account.reload.stripe_customer_id
  end

  test "returns the checkout url on success" do
    account.update!(stripe_customer_id: "cus_123")

    result = service(stripe_client: mock_stripe_client).call

    assert result[:success], "errors: #{result[:errors]}"
    assert_equal "https://checkout.stripe.com/mock", result[:checkout_url]
  end

  test "the session is a one-time payment for the full setup amount" do
    account.update!(stripe_customer_id: "cus_123")
    captured = nil

    service(stripe_client: mock_stripe_client { |params| captured = params }).call

    assert_equal "payment", captured[:mode]
    assert_equal ::Billing::GUIDED_SETUP_CREDIT_CENTS, captured[:line_items].first[:price_data][:unit_amount]
  end

  test "the session metadata carries the guided_setup flag and chosen plan" do
    account.update!(stripe_customer_id: "cus_123")
    captured = nil

    service(stripe_client: mock_stripe_client { |params| captured = params }).call

    assert_equal "true", captured[:metadata][:guided_setup]
    assert_equal plan.slug, captured[:metadata][:plan_slug]
  end

  test "success_url carries Stripe's session-id template so the redirect can verify the session" do
    account.update!(stripe_customer_id: "cus_123")
    captured = nil

    service(stripe_client: mock_stripe_client { |params| captured = params }).call

    assert_includes captured[:success_url], "session_id={CHECKOUT_SESSION_ID}"
  end

  test "handles Stripe errors gracefully" do
    account.update!(stripe_customer_id: "cus_123")
    error_client = Object.new
    def error_client.create_checkout_session(_params)
      raise Stripe::InvalidRequestError.new("bad", nil)
    end

    result = service(stripe_client: error_client).call

    assert_not result[:success]
    assert_includes result[:errors].first, "Stripe error"
  end

  private

  def service(plan_slug: "growth", stripe_client: nil)
    Billing::CreditCheckoutService.new(
      account: account,
      plan_slug: plan_slug,
      urls: { success: "http://test.host/onboarding/confirmation", cancel: "http://test.host/onboarding/guided_setup" },
      stripe_client: stripe_client
    )
  end

  def mock_stripe_client(&block)
    MockStripeClient.new(on_create_session: block)
  end

  def account = @account ||= accounts(:one)
  def plan = @plan ||= plans(:growth)

  class MockStripeClient
    def initialize(on_create_session: nil)
      @on_create_session = on_create_session
    end

    def create_customer(email:, metadata:)
      ::OpenStruct.new(id: "cus_mock123", email: email, metadata: metadata)
    end

    def create_checkout_session(params)
      @on_create_session&.call(params)
      ::OpenStruct.new(id: "cs_mock123", url: "https://checkout.stripe.com/mock")
    end
  end
end
