# frozen_string_literal: true

require_relative "../test_helper"
require "httparty"

# Tests for cross-device identity-based session resolution
# This test simulates the scenario where a user visits from multiple devices
# and after identification, their sessions should be linked across devices
class IdentityCrossDeviceTest < Minitest::Test
  def setup
    @user_email = "crossdevice_#{SecureRandom.hex(8)}@example.com"
    @desktop_visitor_id = "vis_desktop_#{SecureRandom.hex(8)}"
    @mobile_visitor_id = "vis_mobile_#{SecureRandom.hex(8)}"
    @desktop_session_id = "sess_desktop_#{SecureRandom.hex(8)}"
    @desktop_fingerprint = "fp_desktop_#{SecureRandom.hex(16)}"
    @mobile_fingerprint = "fp_mobile_#{SecureRandom.hex(16)}"
  end

  def teardown
    [@desktop_visitor_id, @mobile_visitor_id].each do |vid|
      VerificationHelper.cleanup(visitor_id: vid)
    rescue StandardError
      nil
    end
  end

  # Main test: Cross-device session resolution via identity
  # When tracking an event with `identifier`, should find the desktop session
  # and use it for the mobile event (same user, different device)
  def test_event_with_identifier_resolves_cross_device_session
    skip "Requires local API server" unless api_available?

    # Step 1: Desktop visit - create visitor and session
    desktop_result = create_session(
      visitor_id: @desktop_visitor_id,
      session_id: @desktop_session_id,
      device_fingerprint: @desktop_fingerprint,
      url: "https://example.com/desktop-page"
    )
    assert_equal "accepted", desktop_result["status"], "Desktop session should be created"

    # Step 2: Desktop - identify user (links desktop visitor to identity)
    identify_result = identify_user(
      visitor_id: @desktop_visitor_id,
      user_id: @user_email,
      traits: { email: @user_email, device: "desktop" }
    )
    assert identify_result["success"], "Desktop identify should succeed"

    sleep 1 # Allow async processing

    # Step 3: Mobile visit - track event with identifier (NEW visitor, different device)
    # The identifier should trigger cross-device session lookup and find the desktop session
    event_result = track_event_with_identifier(
      visitor_id: @mobile_visitor_id,
      identifier: { email: @user_email },
      event_type: "page_view",
      url: "https://example.com/mobile-page",
      ip: "192.168.1.200",
      user_agent: "Mobile Safari"
    )

    assert_equal 1, event_result["accepted"], "Event should be accepted"

    sleep 2 # Allow async processing

    # Step 4: Verify mobile visitor is linked to same identity
    desktop_data = VerificationHelper.verify(visitor_id: @desktop_visitor_id)
    mobile_data = VerificationHelper.verify(visitor_id: @mobile_visitor_id)

    assert desktop_data[:visitor][:identity_id], "Desktop visitor should have identity"
    assert mobile_data[:visitor][:identity_id], "Mobile visitor should have identity"
    assert_equal desktop_data[:visitor][:identity_id], mobile_data[:visitor][:identity_id],
      "Both visitors should be linked to the same identity"

    # Step 5: KEY TEST - The mobile event should be assigned to the DESKTOP session
    # This proves cross-device session resolution is working
    mobile_event = mobile_data[:events]&.first
    assert mobile_event, "Mobile visitor should have an event"

    # The event's session_id should be the desktop session (cross-device resolution)
    assert_equal @desktop_session_id, mobile_event[:session_id],
      "Mobile event should use desktop session (cross-device resolution). " \
      "Got session_id: #{mobile_event[:session_id]}, expected: #{@desktop_session_id}"
  end

  # Test: Sessions remain separate without identifier
  def test_sessions_separate_without_identifier
    skip "Requires local API server" unless api_available?

    # Desktop creates session
    create_session(
      visitor_id: @desktop_visitor_id,
      session_id: @desktop_session_id,
      device_fingerprint: @desktop_fingerprint,
      url: "https://example.com/desktop"
    )

    # Identify desktop user
    identify_user(
      visitor_id: @desktop_visitor_id,
      user_id: @user_email,
      traits: { email: @user_email }
    )

    sleep 1

    # Mobile tracks event WITHOUT identifier
    track_event(
      visitor_id: @mobile_visitor_id,
      event_type: "page_view",
      url: "https://example.com/mobile"
    )

    sleep 1

    # Verify visitors are NOT linked (mobile didn't use identifier)
    desktop_data = VerificationHelper.verify(visitor_id: @desktop_visitor_id)
    mobile_data = VerificationHelper.verify(visitor_id: @mobile_visitor_id)

    assert desktop_data[:visitor][:identity_id], "Desktop should have identity"
    assert_nil mobile_data[:visitor][:identity_id], "Mobile should NOT have identity (no identifier)"
  end

  private

  def api_available?
    HTTParty.get("#{TestConfig.api_url}/health")
    true
  rescue StandardError
    false
  end

  def create_session(visitor_id:, session_id:, device_fingerprint:, url:)
    HTTParty.post(
      "#{TestConfig.api_url}/sessions",
      headers: auth_headers,
      body: {
        session: {
          visitor_id: visitor_id,
          session_id: session_id,
          device_fingerprint: device_fingerprint,
          url: url,
          started_at: Time.now.utc.iso8601(6)
        }
      }.to_json
    ).parsed_response
  rescue StandardError => e
    { "success" => false, "error" => e.message }
  end

  def identify_user(visitor_id:, user_id:, traits: {})
    HTTParty.post(
      "#{TestConfig.api_url}/identify",
      headers: auth_headers,
      body: {
        visitor_id: visitor_id,
        user_id: user_id,
        traits: traits
      }.to_json
    ).parsed_response
  rescue StandardError => e
    { "success" => false, "error" => e.message }
  end

  def track_event_with_identifier(visitor_id:, identifier:, event_type:, url:, ip:, user_agent:)
    HTTParty.post(
      "#{TestConfig.api_url}/events",
      headers: auth_headers,
      body: {
        events: [{
          visitor_id: visitor_id,
          event_type: event_type,
          properties: { url: url },
          identifier: identifier,
          ip: ip,
          user_agent: user_agent
        }]
      }.to_json
    ).parsed_response
  rescue StandardError => e
    { "accepted" => 0, "error" => e.message }
  end

  def track_event(visitor_id:, event_type:, url:)
    HTTParty.post(
      "#{TestConfig.api_url}/events",
      headers: auth_headers,
      body: {
        events: [{
          visitor_id: visitor_id,
          event_type: event_type,
          properties: { url: url }
        }]
      }.to_json
    ).parsed_response
  rescue StandardError => e
    { "accepted" => 0, "error" => e.message }
  end

  def auth_headers
    {
      "Authorization" => "Bearer #{TestConfig.api_key}",
      "Content-Type" => "application/json"
    }
  end
end
