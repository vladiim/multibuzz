# frozen_string_literal: true

require "test_helper"
require "ostruct"

class Billing::PortalServiceTest < ActiveSupport::TestCase
  test "returns error when account has no stripe customer" do
    account.update!(stripe_customer_id: nil)

    assert_not result[:success]
    assert_includes result[:errors], "No billing account found"
  end

  test "returns portal url on success" do
    account.update!(stripe_customer_id: "cus_123")
    @stripe_client = mock_stripe_client

    assert result[:success], "Expected success but got: #{result[:errors]}"
    assert_equal "https://billing.stripe.com/mock", result[:portal_url]
  end

  test "passes correct parameters to stripe" do
    account.update!(stripe_customer_id: "cus_123")
    @stripe_client = mock_stripe_client { |params| @captured_params = params }

    result

    assert_equal "cus_123", @captured_params[:customer]
    assert_predicate @captured_params[:return_url], :present?
  end

  test "handles stripe errors gracefully" do
    account.update!(stripe_customer_id: "cus_123")
    @stripe_client = error_stripe_client

    assert_not result[:success]
    assert_includes result[:errors].first, "Stripe error"
  end

  private

  def result
    @result ||= service.call
  end

  def service
    @service ||= Billing::PortalService.new(
      account: account,
      return_url: "http://test.host/dashboard",
      stripe_client: @stripe_client
    )
  end

  def mock_stripe_client(&block)
    MockStripeClient.new(on_create_session: block)
  end

  def error_stripe_client
    client = Object.new
    def client.create_portal_session(_params)
      raise Stripe::InvalidRequestError.new("Customer not found", nil)
    end
    client
  end

  def account
    @account ||= accounts(:one)
  end

  class MockStripeClient
    def initialize(on_create_session: nil)
      @on_create_session = on_create_session
    end

    def create_portal_session(params)
      @on_create_session&.call(params)
      ::OpenStruct.new(url: "https://billing.stripe.com/mock")
    end
  end
end
