require "test_helper"

class Api::V1::EventsControllerTest < ActionDispatch::IntegrationTest
  test "should accept valid events batch" do
    post api_v1_events_path, params: events_payload, headers: auth_headers, as: :json

    assert_response :accepted
    assert_equal 2, json_response["accepted"]
    assert_empty json_response["rejected"]
  end

  test "should return 401 without authorization header" do
    post api_v1_events_path, params: events_payload, as: :json

    assert_response :unauthorized
    assert_equal "Missing Authorization header", json_response["error"]
  end

  test "should return 401 with invalid api key" do
    post api_v1_events_path, params: events_payload, headers: invalid_auth_headers, as: :json

    assert_response :unauthorized
    assert_equal "Invalid or expired API key", json_response["error"]
  end

  test "should return 401 with revoked api key" do
    api_key.revoke!

    post api_v1_events_path, params: events_payload, headers: auth_headers, as: :json

    assert_response :unauthorized
    assert_equal "API key has been revoked", json_response["error"]
  end

  test "should return 400 with missing events key" do
    post api_v1_events_path, params: {}, headers: auth_headers, as: :json

    assert_response :bad_request
    assert_equal "Missing 'events' parameter", json_response["error"]
  end

  test "should return 400 with non-array events" do
    post api_v1_events_path, params: { events: "not an array" }, headers: auth_headers, as: :json

    assert_response :bad_request
    assert_equal "Events must be an array", json_response["error"]
  end

  test "should return 422 with partial failures" do
    payload = {
      events: [
        valid_event_data,
        invalid_event_data
      ]
    }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal 1, json_response["accepted"]
    assert_equal 1, json_response["rejected"].size
  end

  test "should return 422 with all failures" do
    payload = {
      events: [
        invalid_event_data,
        invalid_event_data
      ]
    }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal 0, json_response["accepted"]
    assert_equal 2, json_response["rejected"].size
  end

  test "should record api key usage" do
    old_time = api_key.last_used_at

    post api_v1_events_path, params: events_payload, headers: auth_headers, as: :json

    assert_response :accepted
    assert api_key.reload.last_used_at > old_time
  end

  test "should scope events to authenticated account" do
    post api_v1_events_path, params: events_payload, headers: auth_headers, as: :json

    assert_response :accepted
    created_event = account.events.last
    assert_equal account, created_event.account
  end

  private

  def json_response
    JSON.parse(response.body)
  end

  def auth_headers
    { "Authorization" => "Bearer #{plaintext_key}" }
  end

  def invalid_auth_headers
    { "Authorization" => "Bearer sk_test_invalid123" }
  end

  def events_payload
    {
      events: [
        valid_event_data,
        valid_event_data.merge("visitor_id" => "vis_different", "session_id" => "sess_different")
      ]
    }
  end

  def valid_event_data
    {
      "event_type" => "page_view",
      "visitor_id" => "vis_test_abc123",
      "session_id" => "sess_test_xyz789",
      "timestamp" => "2025-11-07T10:30:45Z",
      "properties" => {
        "url" => "https://example.com/page",
        "utm_source" => "google"
      }
    }
  end

  def invalid_event_data
    { "event_type" => "" }
  end

  def account
    @account ||= accounts(:one)
  end

  def api_key
    @api_key ||= api_keys(:one)
  end

  def plaintext_key
    @plaintext_key ||= begin
      key = "sk_test_#{SecureRandom.hex(16)}"
      api_key.update_column(:key_digest, Digest::SHA256.hexdigest(key))
      key
    end
  end
end
