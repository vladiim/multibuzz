# frozen_string_literal: true

require "test_helper"

class Api::V1::DataControllerTest < ActionDispatch::IntegrationTest
  TEST_KEY = "sk_test_abc123xyz789"
  LIVE_KEY = "sk_live_xyz789abc123"
  REVOKED_KEY = "sk_test_revoked123"
  OTHER_KEY = "sk_test_other456"

  # ==========================================
  # Auth (applies to all 3 endpoints)
  # ==========================================

  test "conversions: 401 without authorization header" do
    get "/api/v1/data/conversions"

    assert_response :unauthorized
    assert_match(/Authorization/i, response.parsed_body["error"])
  end

  test "conversions: 401 with invalid key" do
    get "/api/v1/data/conversions", headers: bearer("sk_test_nope")

    assert_response :unauthorized
  end

  test "conversions: 401 with revoked key" do
    get "/api/v1/data/conversions", headers: bearer(REVOKED_KEY)

    assert_response :unauthorized
  end

  test "funnel: 401 without authorization header" do
    get "/api/v1/data/funnel"

    assert_response :unauthorized
  end

  test "spend: 401 without authorization header" do
    get "/api/v1/data/spend"

    assert_response :unauthorized
  end

  # ==========================================
  # Spend endpoint
  # ==========================================

  test "spend: 200 with documented JSON shape" do # rubocop:disable Minitest/MultipleAssertions
    get "/api/v1/data/spend", headers: bearer(LIVE_KEY)

    assert_response :success
    body = response.parsed_body

    assert body.key?("data")
    assert body.key?("meta")
    assert body["meta"].key?("total_count")
    assert body["meta"].key?("page")
    assert body["meta"].key?("per_page")
    assert body["meta"].key?("total_pages")
  end

  test "spend: test key returns test rows only" do
    get "/api/v1/data/spend", headers: bearer(TEST_KEY)

    assert_response :success
    names = response.parsed_body["data"].map { |r| r["campaign_name"] }.uniq

    assert_equal [ "Test Campaign" ], names
  end

  test "spend: live key excludes test rows" do
    get "/api/v1/data/spend", headers: bearer(LIVE_KEY)

    assert_response :success
    names = response.parsed_body["data"].map { |r| r["campaign_name"] }

    assert_not_includes names, "Test Campaign"
  end

  test "spend: never returns other account rows" do
    get "/api/v1/data/spend", headers: bearer(LIVE_KEY)

    assert_response :success
    names = response.parsed_body["data"].map { |r| r["campaign_name"] }

    assert_not_includes names, "Beta Search"
  end

  # ==========================================
  # Conversions endpoint
  # ==========================================

  test "conversions: 200 with valid live key" do
    get "/api/v1/data/conversions", headers: bearer(LIVE_KEY)

    assert_response :success
    assert response.parsed_body.key?("data")
    assert response.parsed_body.key?("meta")
  end

  # ==========================================
  # Funnel endpoint
  # ==========================================

  test "funnel: 200 with valid live key" do
    get "/api/v1/data/funnel", headers: bearer(LIVE_KEY)

    assert_response :success
    assert response.parsed_body.key?("data")
    assert response.parsed_body.key?("meta")
  end

  test "funnel: respects funnel query param" do
    get "/api/v1/data/funnel", headers: bearer(LIVE_KEY), params: { funnel: "checkout" }

    assert_response :success
  end

  # ==========================================
  # Pagination
  # ==========================================

  test "spend: per_page param respected" do
    get "/api/v1/data/spend", headers: bearer(LIVE_KEY), params: { per_page: 1 }

    assert_response :success
    assert_equal 1, response.parsed_body["meta"]["per_page"]
  end

  test "spend: per_page over 1000 clamps to 1000" do
    get "/api/v1/data/spend", headers: bearer(LIVE_KEY), params: { per_page: 5000 }

    assert_response :success
    assert_equal 1000, response.parsed_body["meta"]["per_page"]
  end

  # ==========================================
  # Date validation (400, not 500)
  # ==========================================

  test "conversions: 400 with invalid start_date" do
    get "/api/v1/data/conversions",
        headers: bearer(LIVE_KEY),
        params: { start_date: "banana", end_date: "2026-05-14" }

    assert_response :bad_request
    assert_match(/date/i, response.parsed_body["error"])
  end

  test "conversions: 400 with invalid end_date" do
    get "/api/v1/data/conversions",
        headers: bearer(LIVE_KEY),
        params: { start_date: "2026-05-01", end_date: "banana" }

    assert_response :bad_request
  end

  test "funnel: 400 with invalid start_date" do
    get "/api/v1/data/funnel",
        headers: bearer(LIVE_KEY),
        params: { start_date: "banana", end_date: "2026-05-14" }

    assert_response :bad_request
  end

  test "spend: 400 with invalid start_date" do
    get "/api/v1/data/spend",
        headers: bearer(LIVE_KEY),
        params: { start_date: "banana", end_date: "2026-05-14" }

    assert_response :bad_request
  end

  private

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end
end
