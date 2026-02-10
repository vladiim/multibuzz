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

  test "should return 402 when account billing is blocked" do
    account.update_column(:billing_status, Account.billing_statuses[:cancelled])

    post api_v1_events_path, params: events_payload, headers: auth_headers, as: :json

    assert_response :payment_required
    assert_equal "Account cannot accept events", json_response["error"]
    assert_equal true, json_response["billing_blocked"]
  end

  test "should preserve visitor_id from SDK payload" do
    sdk_session_id = "sdk_session_#{SecureRandom.hex(16)}"

    payload = {
      events: [
        valid_event_data.merge(
          "visitor_id" => visitor.visitor_id,
          "session_id" => sdk_session_id
        )
      ]
    }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_response :accepted

    created_event = account.events.unscoped.where(account: account).test_data.order(created_at: :desc).first
    assert_equal visitor.visitor_id, created_event.visitor.visitor_id
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

  test "should reject event when visitor_id not provided and visitor not found" do
    payload = { events: [event_without_ids] }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json

    assert_response :accepted
    assert_equal 0, json_response["accepted"]
    assert_equal 1, json_response["rejected"].size
    assert_includes json_response["rejected"].first["errors"], "Visitor not found"
  end

  test "should reuse visitor_id from cookie when visitor exists" do
    # First create a session/visitor via the sessions endpoint or use existing
    payload = { events: [event_without_ids.merge("visitor_id" => visitor.visitor_id)] }

    post api_v1_events_path, params: payload, headers: auth_headers, as: :json
    assert_response :accepted
    assert_equal 1, json_response["accepted"]

    # Second request with same visitor_id
    second_payload = { events: [event_without_ids.merge("visitor_id" => visitor.visitor_id, "event_type" => "button_click")] }

    post api_v1_events_path,
      params: second_payload,
      headers: auth_headers.merge("Cookie" => "_mbuzz_vid=#{visitor.visitor_id}"),
      as: :json

    assert_response :accepted
    assert_equal 1, json_response["accepted"]

    events = account.events.unscoped.where(account: account).test_data.order(created_at: :asc).last(2)
    assert_equal events.first.visitor_id, events.last.visitor_id
  end

  test "should reject events with unknown visitor_id from cookie" do
    unknown_visitor_id = "vis_unknown_#{SecureRandom.hex(16)}"

    payload = { events: [event_without_ids] }
    post api_v1_events_path,
      params: payload,
      headers: auth_headers.merge("Cookie" => "_mbuzz_vid=#{unknown_visitor_id}"),
      as: :json

    assert_response :accepted
    assert_equal 0, json_response["accepted"]
    assert_equal 1, json_response["rejected"].size
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
    # Use existing visitor_two from payload, even though cookie has visitor_one's ID
    payload = {
      events: [event_without_ids.merge("visitor_id" => visitor_two.visitor_id)]
    }

    post api_v1_events_path,
      params: payload,
      headers: auth_headers.merge("Cookie" => "_mbuzz_vid=#{visitor.visitor_id}"),
      as: :json

    assert_response :accepted

    created_event = account.events.unscoped.where(account: account).test_data.last
    assert_equal visitor_two.visitor_id, created_event.visitor.visitor_id,
      "Explicit visitor_id in payload should take precedence over cookie"
  end

  # Server-side session resolution tests

  test "should resolve session server-side using ip and user_agent" do
    visitor_id = "vis_server_side_#{SecureRandom.hex(8)}"

    # Create existing visitor and session with matching device fingerprint
    visitor = account.visitors.create!(
      visitor_id: visitor_id,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      is_test: true
    )

    device_fingerprint = Digest::SHA256.hexdigest("127.0.0.0|Rails Testing")[0, 32]
    existing_session = account.sessions.create!(
      visitor: visitor,
      session_id: "sess_existing_#{SecureRandom.hex(8)}",
      started_at: 10.minutes.ago,
      last_activity_at: 10.minutes.ago,
      device_fingerprint: device_fingerprint,
      is_test: true
    )

    payload = {
      events: [
        event_without_ids.merge(
          "visitor_id" => visitor_id,
          "session_id" => "sess_client_should_be_ignored"
        )
      ]
    }

    post api_v1_events_path, params: payload, headers: auth_headers_with_user_agent, as: :json

    assert_response :accepted

    created_event = account.events.unscoped.where(account: account).test_data.last
    assert_equal existing_session.session_id, created_event.session.session_id,
      "Should use existing session, not client-sent session_id"
  end

  test "should create new session when existing session expired" do
    visitor_id = "vis_expired_#{SecureRandom.hex(8)}"

    visitor = account.visitors.create!(
      visitor_id: visitor_id,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      is_test: true
    )

    device_fingerprint = Digest::SHA256.hexdigest("127.0.0.0|Rails Testing")[0, 32]
    old_session = account.sessions.create!(
      visitor: visitor,
      session_id: "sess_old_#{SecureRandom.hex(8)}",
      started_at: 1.hour.ago,
      last_activity_at: 45.minutes.ago,  # Expired (> 30 min)
      device_fingerprint: device_fingerprint,
      is_test: true
    )

    payload = {
      events: [event_without_ids.merge("visitor_id" => visitor_id)]
    }

    post api_v1_events_path, params: payload, headers: auth_headers_with_user_agent, as: :json

    assert_response :accepted

    created_event = account.events.unscoped.where(account: account).test_data.last
    assert_not_equal old_session.session_id, created_event.session.session_id,
      "Should create new session when existing session expired"
  end

  test "should generate deterministic session_id for concurrent requests" do
    visitor_id = "vis_concurrent_#{SecureRandom.hex(8)}"

    # Create visitor but no session
    account.visitors.create!(
      visitor_id: visitor_id,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      is_test: true
    )

    # Send two events in same request (simulating concurrent page loads)
    payload = {
      events: [
        event_without_ids.merge("visitor_id" => visitor_id, "event_type" => "page_view"),
        event_without_ids.merge("visitor_id" => visitor_id, "event_type" => "button_click")
      ]
    }

    post api_v1_events_path, params: payload, headers: auth_headers_with_user_agent, as: :json

    assert_response :accepted

    events = account.events.unscoped.where(account: account).test_data.order(created_at: :asc).last(2)
    assert_equal events.first.session_id, events.last.session_id,
      "Concurrent events should get same deterministic session_id"
  end

  test "should update last_activity_at on session for each event" do
    visitor_id = "vis_activity_#{SecureRandom.hex(8)}"

    visitor = account.visitors.create!(
      visitor_id: visitor_id,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      is_test: true
    )

    device_fingerprint = Digest::SHA256.hexdigest("127.0.0.0|Rails Testing")[0, 32]
    session = account.sessions.create!(
      visitor: visitor,
      session_id: "sess_activity_#{SecureRandom.hex(8)}",
      started_at: 20.minutes.ago,
      last_activity_at: 20.minutes.ago,
      device_fingerprint: device_fingerprint,
      is_test: true
    )

    old_activity = session.last_activity_at

    payload = {
      events: [event_without_ids.merge("visitor_id" => visitor_id)]
    }

    post api_v1_events_path, params: payload, headers: auth_headers_with_user_agent, as: :json

    assert_response :accepted
    assert session.reload.last_activity_at > old_activity,
      "Session last_activity_at should be updated"
  end

  test "should store device_fingerprint on new session" do
    visitor_id = "vis_fingerprint_#{SecureRandom.hex(8)}"

    account.visitors.create!(
      visitor_id: visitor_id,
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      is_test: true
    )

    payload = {
      events: [event_without_ids.merge("visitor_id" => visitor_id)]
    }

    post api_v1_events_path, params: payload, headers: auth_headers_with_user_agent, as: :json

    assert_response :accepted

    created_event = account.events.unscoped.where(account: account).test_data.last
    assert created_event.session.device_fingerprint.present?,
      "New session should have device_fingerprint stored"
    assert_equal 32, created_event.session.device_fingerprint.length
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

  def auth_headers_with_user_agent
    auth_headers.merge("User-Agent" => "Rails Testing")
  end

  def invalid_auth_headers
    { "Authorization" => "Bearer sk_test_invalid123" }
  end

  def events_payload
    {
      events: [
        valid_event_data,
        valid_event_data.merge("visitor_id" => visitor_two.visitor_id, "session_id" => "sess_different_#{SecureRandom.hex(4)}")
      ]
    }
  end

  def valid_event_data
    {
      "event_type" => "page_view",
      "visitor_id" => visitor.visitor_id,
      "session_id" => "sess_test_#{SecureRandom.hex(4)}",
      "timestamp" => "2025-11-07T10:30:45Z",
      "properties" => {
        "url" => "https://example.com/page",
        "utm_source" => "google"
      }
    }
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def visitor_two
    @visitor_two ||= visitors(:two)
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
