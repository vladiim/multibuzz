require "test_helper"

class Api::V1::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
  end

  test "should accept valid events batch" do
    post api_v1_events_path, params: events_payload, headers: auth_headers, as: :json

    assert_response :accepted
    assert_equal 2, json_response["accepted"]
    assert_empty json_response["rejected"]
    assert_equal 2, account.events.unscoped.where(account: account).test_data.count
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

  test "should return 202 with partial failures" do
    payload = {
      events: [
        valid_event_data,
        invalid_event_data
      ]
    }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_response :accepted
    assert_equal 1, json_response["accepted"]
    assert_equal 1, json_response["rejected"].size
  end

  test "should return 202 with all failures" do
    payload = {
      events: [
        invalid_event_data,
        invalid_event_data
      ]
    }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_response :accepted
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
    created_event = account.events.unscoped.where(account: account).test_data.last
    assert_equal account, created_event.account
  end

  test "should return events array with IDs for accepted events" do
    post api_v1_events_path, params: events_payload, headers: auth_headers, as: :json

    assert_response :accepted
    assert_equal 2, json_response["events"].size

    first_event = json_response["events"].first
    assert_match(/^evt_/, first_event["id"])
    assert_equal "page_view", first_event["event_type"]
    assert_equal "accepted", first_event["status"]
  end

  test "should return rejected events with details" do
    payload = { events: [invalid_event_data] }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_response :accepted
    assert_empty json_response["events"]
    assert_equal 1, json_response["rejected"].size

    rejected = json_response["rejected"].first
    assert_equal 0, rejected["index"]
    assert_equal "rejected", rejected["status"]
  end

  test "should return 401 with suspended account" do
    post api_v1_events_path, params: events_payload, headers: suspended_auth_headers, as: :json

    assert_response :unauthorized
    assert_equal "Account suspended", json_response["error"]
  end

  test "should preserve visitor_id from SDK payload" do
    sdk_visitor_id = "sdk_visitor_#{SecureRandom.hex(16)}"
    sdk_session_id = "sdk_session_#{SecureRandom.hex(16)}"

    payload = {
      events: [
        valid_event_data.merge(
          "visitor_id" => sdk_visitor_id,
          "session_id" => sdk_session_id
        )
      ]
    }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_response :accepted

    created_event = account.events.order(created_at: :desc).first
    assert_equal sdk_visitor_id, created_event.visitor.visitor_id
    assert_equal sdk_session_id, created_event.session.session_id
  end

  # Cookie handling tests - visitor persistence

  test "should set visitor cookie in response" do
    payload = { events: [event_without_ids] }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_response :accepted
    assert response.headers["Set-Cookie"].present?
    assert_match(/_mbuzz_vid=/, response.headers["Set-Cookie"])
  end

  test "should set session cookie in response" do
    payload = { events: [event_without_ids] }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_response :accepted
    assert_match(/_mbuzz_sid=/, response.headers["Set-Cookie"])
  end

  test "should generate visitor_id when not provided and no cookie" do
    payload = { events: [event_without_ids] }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_response :accepted

    created_event = account.events.unscoped.where(account: account).test_data.last
    assert created_event.visitor.visitor_id.present?
    assert_equal 64, created_event.visitor.visitor_id.length
  end

  test "should reuse visitor_id from cookie on subsequent requests" do
    first_payload = { events: [event_without_ids] }

    post api_v1_events_path, params: first_payload, headers: auth_headers, as: :json
    assert_response :accepted

    first_visitor_id = extract_cookie_value("_mbuzz_vid")
    assert first_visitor_id.present?

    second_payload = { events: [event_without_ids.merge("event_type" => "button_click")] }

    post api_v1_events_path,
      params: second_payload,
      headers: auth_headers.merge("Cookie" => "_mbuzz_vid=#{first_visitor_id}"),
      as: :json

    assert_response :accepted

    events = account.events.unscoped.where(account: account).test_data.order(created_at: :asc).last(2)
    assert_equal events.first.visitor_id, events.last.visitor_id
  end

  test "should create different visitors for requests without cookies" do
    # Simulate two different browser sessions by clearing cookies between requests
    first_payload = { events: [event_without_ids] }
    post api_v1_events_path, params: first_payload, headers: auth_headers, as: :json
    assert_response :accepted

    first_visitor_id = account.events.unscoped.where(account: account).test_data.last.visitor.visitor_id

    # Clear the cookie jar to simulate a new browser/user
    cookies.delete("_mbuzz_vid")
    cookies.delete("_mbuzz_sid")

    second_payload = { events: [event_without_ids.merge("event_type" => "button_click")] }
    post api_v1_events_path, params: second_payload, headers: auth_headers, as: :json
    assert_response :accepted

    second_visitor_id = account.events.unscoped.where(account: account).test_data.last.visitor.visitor_id

    refute_equal first_visitor_id, second_visitor_id,
      "Requests without cookies should create different visitors"
  end

  test "should set HttpOnly flag on visitor cookie" do
    payload = { events: [event_without_ids] }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_match(/HttpOnly/i, response.headers["Set-Cookie"])
  end

  test "should set SameSite=Lax on visitor cookie" do
    payload = { events: [event_without_ids] }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_match(/SameSite=Lax/i, response.headers["Set-Cookie"])
  end

  test "should use visitor_id from payload even when cookie present" do
    sdk_visitor_id = "sdk_explicit_visitor_#{SecureRandom.hex(16)}"
    cookie_visitor_id = "cookie_visitor_#{SecureRandom.hex(16)}"

    payload = {
      events: [event_without_ids.merge("visitor_id" => sdk_visitor_id)]
    }

    post api_v1_events_path,
      params: payload,
      headers: auth_headers.merge("Cookie" => "_mbuzz_vid=#{cookie_visitor_id}"),
      as: :json

    assert_response :accepted

    created_event = account.events.unscoped.where(account: account).test_data.last
    assert_equal sdk_visitor_id, created_event.visitor.visitor_id,
      "Explicit visitor_id in payload should take precedence over cookie"
  end

  private

  def extract_cookie_value(cookie_name)
    cookie_header = response.headers["Set-Cookie"]
    return nil unless cookie_header

    match = cookie_header.match(/#{cookie_name}=([^;]+)/)
    match ? match[1] : nil
  end

  def event_without_ids
    {
      "event_type" => "page_view",
      "timestamp" => Time.current.utc.iso8601,
      "properties" => {
        "url" => "https://example.com/page"
      }
    }
  end

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

  def suspended_auth_headers
    { "Authorization" => "Bearer sk_test_suspended789" }
  end
end
