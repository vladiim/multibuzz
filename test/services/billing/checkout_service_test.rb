require "test_helper"
require "ostruct"

class Billing::CheckoutServiceTest < ActiveSupport::TestCase
  test "returns error when plan not found" do
    result = service(plan_slug: "nonexistent").call

    assert_not result[:success]
    assert_includes result[:errors], "Plan not found"
  end

  test "returns error when plan is free" do
    result = service(plan_slug: "free").call

    assert_not result[:success]
    assert_includes result[:errors], "Cannot checkout free plan"
  end

  test "returns error when plan has no stripe price" do
    starter_plan.update!(stripe_price_id: nil)

    result = service.call

    assert_not result[:success]
    assert_includes result[:errors], "Plan not configured for billing"
  end

  test "creates stripe customer if not exists" do
    account.update!(stripe_customer_id: nil)

    result = service(stripe_client: mock_stripe_client).call

    assert result[:success]
    assert_equal "cus_mock123", account.reload.stripe_customer_id
  end

  test "reuses existing stripe customer" do
    account.update!(stripe_customer_id: "cus_existing")

    client = mock_stripe_client(should_create_customer: false)
    result = service(stripe_client: client).call

    assert result[:success]
    assert_equal "cus_existing", account.reload.stripe_customer_id
  end

  test "returns checkout session details on success" do
    account.update!(stripe_customer_id: "cus_123")

    result = service(stripe_client: mock_stripe_client).call

    assert result[:success], "Expected success but got: #{result[:errors]}"
    assert_equal "cs_mock123", result[:session_id]
    assert_equal "https://checkout.stripe.com/mock", result[:checkout_url]
  end

  test "passes correct parameters to stripe" do
    account.update!(stripe_customer_id: "cus_123")
    starter_plan.update!(stripe_price_id: "price_starter123")

    captured_params = nil
    client = mock_stripe_client do |params|
      captured_params = params
    end

    service(stripe_client: client).call

    assert_equal "cus_123", captured_params[:customer]
    assert_equal [{ price: "price_starter123", quantity: 1 }], captured_params[:line_items]
    assert_equal "subscription", captured_params[:mode]
    assert captured_params[:success_url].include?("{CHECKOUT_SESSION_ID}")
    assert captured_params[:cancel_url].present?
  end

  test "includes account metadata in session" do
    account.update!(stripe_customer_id: "cus_123")

    captured_params = nil
    client = mock_stripe_client { |params| captured_params = params }

    service(stripe_client: client).call

    assert_equal account.prefix_id, captured_params[:metadata][:account_id]
    assert_equal starter_plan.slug, captured_params[:metadata][:plan_slug]
  end

  test "handles stripe errors gracefully" do
    account.update!(stripe_customer_id: "cus_123")

    error_client = Object.new
    def error_client.create_checkout_session(_params)
      raise Stripe::InvalidRequestError.new("Invalid request", nil)
    end

    result = service(stripe_client: error_client).call

    assert_not result[:success]
    assert result[:errors].first.include?("Stripe error")
  end

  private

  def service(plan_slug: "starter", stripe_client: nil)
    Billing::CheckoutService.new(
      account: account,
      plan_slug: plan_slug,
      user: user,
      success_url: "http://test.host/billing/success?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: "http://test.host/billing/cancel",
      stripe_client: stripe_client
    )
  end

  def mock_stripe_client(should_create_customer: true, &block)
    MockStripeClient.new(
      should_create_customer: should_create_customer,
      on_create_session: block
    )
  end

  def account
    @account ||= accounts(:one)
  end

  def user
    @user ||= users(:one)
  end

  def starter_plan
    @starter_plan ||= plans(:starter)
  end

  class MockStripeClient
    def initialize(should_create_customer: true, on_create_session: nil)
      @should_create_customer = should_create_customer
      @on_create_session = on_create_session
    end

    def create_customer(email:, metadata:)
      return nil unless @should_create_customer

      ::OpenStruct.new(id: "cus_mock123")
    end

    def create_checkout_session(params)
      @on_create_session&.call(params)
      ::OpenStruct.new(id: "cs_mock123", url: "https://checkout.stripe.com/mock")
    end
  end
end
