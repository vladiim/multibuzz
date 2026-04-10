# frozen_string_literal: true

require "test_helper"

class Api::Internal::ConsentControllerTest < ActionDispatch::IntegrationTest
  VALID_PAYLOAD = {
    "ad" => "denied",
    "analytics" => "denied",
    "ad_user_data" => "denied",
    "ad_personalization" => "denied"
  }.freeze

  test "returns 201 on a valid consent decision" do
    post_consent

    assert_response :created
  end

  test "creates a consent log row" do
    assert_difference -> { ConsentLog.count }, 1 do
      post_consent
    end
  end

  test "stores the consent payload as submitted" do
    post_consent

    assert_equal VALID_PAYLOAD, ConsentLog.last.consent_payload
  end

  test "stores the banner version" do
    post_consent

    assert_equal "v1", ConsentLog.last.banner_version
  end

  test "stores a hashed IP, never the raw IP" do
    post_consent

    log = ConsentLog.last

    refute_includes log.ip_hash, "."
    refute_predicate log.ip_hash, :empty?
    assert_equal 64, log.ip_hash.length
  end

  test "stores the country derived from CF-IPCountry header" do
    post_consent(headers: { "CF-IPCountry" => "FR" })

    assert_equal "FR", ConsentLog.last.country
  end

  test "stores the user agent" do
    post_consent(headers: { "User-Agent" => "Mozilla/5.0 TestBrowser" })

    assert_equal "Mozilla/5.0 TestBrowser", ConsentLog.last.user_agent
  end

  test "stores the visitor id when present in payload" do
    post_consent(visitor_id: "vis_abc123def")

    assert_equal "vis_abc123def", ConsentLog.last.visitor_id
  end

  test "returns 422 when payload is missing" do
    post "/api/internal/consent",
      params: { banner_version: "v1" }.to_json,
      headers: json_headers

    assert_response :unprocessable_content
  end

  test "returns 422 when banner version is missing" do
    post "/api/internal/consent",
      params: { payload: VALID_PAYLOAD }.to_json,
      headers: json_headers

    assert_response :unprocessable_content
  end

  private

  def post_consent(visitor_id: nil, headers: {})
    post "/api/internal/consent",
      params: { payload: VALID_PAYLOAD, banner_version: "v1", visitor_id: visitor_id }.to_json,
      headers: json_headers.merge(headers)
  end

  def json_headers
    { "Content-Type" => "application/json", "Accept" => "application/json" }
  end
end
