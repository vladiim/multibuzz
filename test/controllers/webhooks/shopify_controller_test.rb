# frozen_string_literal: true

require "test_helper"

class WebhooksShopifyControllerTest < ActionDispatch::IntegrationTest
  setup do
    @webhook_secret = "shpss_test_webhook_secret"
    account.update!(
      shopify_domain: "test-store.myshopify.com",
      shopify_webhook_secret: @webhook_secret
    )
  end

  test "returns 401 when signature is missing" do
    post webhooks_shopify_path,
      params: order_paid_payload.to_json,
      headers: json_headers

    assert_response :unauthorized
    assert_includes response.parsed_body["error"], "signature"
  end

  test "returns 401 when signature is invalid" do
    post webhooks_shopify_path,
      params: order_paid_payload.to_json,
      headers: json_headers.merge("HTTP_X_SHOPIFY_HMAC_SHA256" => "invalid")

    assert_response :unauthorized
    assert_includes response.parsed_body["error"], "signature"
  end

  test "returns 401 when shop domain not found" do
    account.update!(shopify_domain: nil)

    post webhooks_shopify_path,
      params: order_paid_payload.to_json,
      headers: headers_with_valid_signature(order_paid_payload)

    assert_response :unauthorized
    assert_includes response.parsed_body["error"], "Unknown shop"
  end

  test "returns 200 and creates conversion for orders/paid webhook" do
    create_visitor_with_session

    assert_difference "Conversion.count", 1 do
      post webhooks_shopify_path,
        params: order_paid_payload.to_json,
        headers: headers_with_valid_signature(order_paid_payload, topic: "orders/paid")
    end

    assert_response :ok
    assert_equal({ "received" => true }, response.parsed_body)

    conversion = Conversion.last

    assert_equal "purchase", conversion.conversion_type
    assert_in_delta(99.99, conversion.revenue.to_f)
    assert_equal visitor.id, conversion.visitor_id
    assert_equal "12345", conversion.properties["shopify_order_id"]
  end

  test "skips duplicate orders (idempotency via shopify_order_id)" do
    create_visitor_with_session
    Conversion.create!(
      account: account,
      visitor_id: visitor.id,
      session_id: session.id,
      conversion_type: "purchase",
      revenue: 99.99,
      converted_at: Time.current,
      properties: { "shopify_order_id" => "12345" }
    )

    assert_no_difference "Conversion.count" do
      post webhooks_shopify_path,
        params: order_paid_payload.to_json,
        headers: headers_with_valid_signature(order_paid_payload, topic: "orders/paid")
    end

    assert_response :ok
  end

  test "handles missing visitor_id in note_attributes gracefully" do
    payload = order_paid_payload.merge(note_attributes: [])

    post webhooks_shopify_path,
      params: payload.to_json,
      headers: headers_with_valid_signature(payload, topic: "orders/paid")

    assert_response :ok
    assert_predicate response.parsed_body["warning"], :present?
    assert_includes response.parsed_body["warning"], "no identity found for email"
  end

  test "creates conversion using email fallback when no note_attributes" do
    # Create identity with matching email and linked visitor
    identity = account.identities.create!(
      external_id: "shopify_67890",
      traits: { "email" => "customer@example.com" },
      first_identified_at: 1.day.ago,
      last_identified_at: 1.hour.ago
    )
    v = account.visitors.create!(
      visitor_id: SecureRandom.hex(32),
      identity: identity,
      first_seen_at: 1.day.ago,
      last_seen_at: 1.hour.ago
    )
    v.sessions.create!(
      account: account,
      session_id: SecureRandom.hex(32),
      started_at: 1.hour.ago,
      initial_utm: { "utm_source" => "google" },
      initial_referrer: nil
    )

    payload = order_paid_payload.merge(note_attributes: [])

    assert_difference "Conversion.count", 1 do
      post webhooks_shopify_path,
        params: payload.to_json,
        headers: headers_with_valid_signature(payload, topic: "orders/paid")
    end

    assert_response :ok
    assert_equal({ "received" => true }, response.parsed_body)

    conversion = Conversion.last

    assert_equal v.id, conversion.visitor_id
  end

  test "returns 200 for unknown webhook topics" do
    post webhooks_shopify_path,
      params: { id: "123" }.to_json,
      headers: headers_with_valid_signature({ id: "123" }, topic: "unknown/topic")

    assert_response :ok
  end

  private

  def order_paid_payload
    @order_paid_payload ||= {
      id: 12345,
      order_number: 1001,
      total_price: "99.99",
      currency: "USD",
      customer: {
        id: 67890,
        email: "customer@example.com"
      },
      note_attributes: [
        { name: "_mbuzz_visitor_id", value: visitor_id },
        { name: "_mbuzz_session_id", value: session_id }
      ],
      line_items: [
        { title: "Test Product", quantity: 1, price: "99.99" }
      ]
    }
  end

  def visitor_id
    @visitor_id ||= SecureRandom.hex(32)
  end

  def session_id
    @session_id ||= SecureRandom.hex(32)
  end

  def json_headers
    { "CONTENT_TYPE" => "application/json" }
  end

  def headers_with_valid_signature(payload, topic: "orders/paid")
    body = payload.to_json
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest("SHA256", @webhook_secret, body)
    )

    json_headers.merge(
      "HTTP_X_SHOPIFY_HMAC_SHA256" => signature,
      "HTTP_X_SHOPIFY_TOPIC" => topic,
      "HTTP_X_SHOPIFY_SHOP_DOMAIN" => "test-store.myshopify.com"
    )
  end

  def account
    @account ||= accounts(:one)
  end

  def visitor
    @visitor ||= account.visitors.find_by(visitor_id: visitor_id)
  end

  def session
    @session ||= visitor&.sessions&.first
  end

  def create_visitor_with_session
    @visitor = account.visitors.create!(
      visitor_id: visitor_id,
      first_seen_at: 1.hour.ago,
      last_seen_at: Time.current
    )
    @session = @visitor.sessions.create!(
      account: account,
      session_id: session_id,
      started_at: 1.hour.ago,
      initial_utm: { "utm_source" => "google", "utm_medium" => "cpc" },
      initial_referrer: "https://google.com"
    )
  end
end
