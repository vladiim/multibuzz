# frozen_string_literal: true

require "test_helper"

class Mcp::ServerControllerTest < ActionDispatch::IntegrationTest
  TEST_KEY = "sk_test_abc123xyz789"
  REVOKED_KEY = "sk_test_revoked123"
  SUSPENDED_KEY = "sk_test_suspended789"

  # --- auth boundary ---

  test "401 without authorization header" do
    post "/mcp", params: initialize_request, as: :json

    assert_response :unauthorized
  end

  test "401 with invalid key" do
    post "/mcp", params: initialize_request, headers: bearer("sk_test_nope"), as: :json

    assert_response :unauthorized
  end

  test "401 with revoked key" do
    post "/mcp", params: initialize_request, headers: bearer(REVOKED_KEY), as: :json

    assert_response :unauthorized
  end

  test "401 with suspended account key" do
    post "/mcp", params: initialize_request, headers: bearer(SUSPENDED_KEY), as: :json

    assert_response :unauthorized
  end

  # --- handshake ---

  test "valid key completes the initialize handshake" do
    post "/mcp", params: initialize_request, headers: bearer(TEST_KEY), as: :json

    assert_response :success
    result = response.parsed_body["result"]

    assert_equal "mbuzz", result.dig("serverInfo", "name")
    assert_predicate result["capabilities"], :present?
  end

  test "tools/list advertises the three data tools" do
    post "/mcp", params: tools_list_request, headers: bearer(TEST_KEY), as: :json

    assert_response :success
    names = response.parsed_body["result"]["tools"].map { |tool| tool["name"] }

    assert_equal %w[mbuzz_get_conversions mbuzz_get_funnel mbuzz_get_spend], names.sort
  end

  test "tools/call dispatches a tool and returns its structured content" do
    post "/mcp", params: spend_call_request, headers: bearer(TEST_KEY), as: :json

    assert_response :success
    result = response.parsed_body["result"]

    assert_not result["isError"]
    assert_kind_of Array, result.dig("structuredContent", "data")
  end

  test "a notification yields an empty 202 response" do
    post "/mcp", params: initialized_notification, headers: bearer(TEST_KEY), as: :json

    assert_response :accepted
    assert_empty response.body
  end

  private

  def bearer(key) = { "Authorization" => "Bearer #{key}" }

  def initialize_request
    {
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "test-client", version: "1.0" }
      }
    }
  end

  def tools_list_request
    { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }
  end

  def spend_call_request
    { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "mbuzz_get_spend", arguments: {} } }
  end

  def initialized_notification
    { jsonrpc: "2.0", method: "notifications/initialized" }
  end
end
