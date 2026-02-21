# frozen_string_literal: true

require "test_helper"

class WebhooksStripeControllerTest < ActionDispatch::IntegrationTest
  setup do
    @webhook_secret = "whsec_test_secret"
    Webhooks::StripeController.webhook_secret_override = @webhook_secret
  end

  teardown do
    Webhooks::StripeController.webhook_secret_override = nil
  end

  test "returns 400 when signature is missing" do
    post webhooks_stripe_path, params: valid_event_payload.to_json, headers: json_headers

    assert_response :bad_request
    assert_includes response.parsed_body["error"], "signature"
  end

  test "returns 400 when signature is invalid" do
    post webhooks_stripe_path,
      params: valid_event_payload.to_json,
      headers: json_headers.merge("HTTP_STRIPE_SIGNATURE" => "invalid_signature")

    assert_response :bad_request
    assert_includes response.parsed_body["error"], "signature"
  end

  test "returns 200 and processes valid webhook" do
    account.update!(stripe_customer_id: "cus_test123")

    post webhooks_stripe_path,
      params: valid_event_payload.to_json,
      headers: headers_with_valid_signature(valid_event_payload)

    assert_response :ok
    assert_equal({ "received" => true }, response.parsed_body)
  end

  test "creates billing event for idempotency" do
    account.update!(stripe_customer_id: "cus_test123")

    assert_difference "BillingEvent.count", 1 do
      post webhooks_stripe_path,
        params: valid_event_payload.to_json,
        headers: headers_with_valid_signature(valid_event_payload)
    end

    billing_event = BillingEvent.last

    assert_equal "evt_test123", billing_event.stripe_event_id
    assert_equal "invoice.paid", billing_event.event_type
  end

  test "skips duplicate events (idempotency)" do
    account.update!(stripe_customer_id: "cus_test123")
    BillingEvent.create!(
      account: account,
      stripe_event_id: "evt_test123",
      event_type: "invoice.paid",
      processed_at: Time.current
    )

    assert_no_difference "BillingEvent.count" do
      post webhooks_stripe_path,
        params: valid_event_payload.to_json,
        headers: headers_with_valid_signature(valid_event_payload)
    end

    assert_response :ok
  end

  test "returns 200 for unknown event types" do
    payload = valid_event_payload.merge(type: "unknown.event.type")

    post webhooks_stripe_path,
      params: payload.to_json,
      headers: headers_with_valid_signature(payload)

    assert_response :ok
  end

  private

  def valid_event_payload
    @valid_event_payload ||= {
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

  def json_headers
    { "CONTENT_TYPE" => "application/json" }
  end

  def headers_with_valid_signature(payload)
    timestamp = Time.current.to_i
    signed_payload = "#{timestamp}.#{payload.to_json}"
    signature = OpenSSL::HMAC.hexdigest("SHA256", @webhook_secret, signed_payload)

    json_headers.merge(
      "HTTP_STRIPE_SIGNATURE" => "t=#{timestamp},v1=#{signature}"
    )
  end

  def account
    @account ||= accounts(:one)
  end
end
