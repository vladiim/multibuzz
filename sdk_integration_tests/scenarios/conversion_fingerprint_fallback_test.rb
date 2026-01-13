# frozen_string_literal: true

require_relative "../test_helper"
require "httparty"

# Tests for conversion tracking with fingerprint-based visitor fallback
# When visitor_id is not found, should fall back to finding visitor via
# recent session matching the same device fingerprint (ip + user_agent)
class ConversionFingerprintFallbackTest < Minitest::Test
  def setup
    @visitor_id = "vis_conv_fp_#{SecureRandom.hex(8)}"
    @session_id = "sess_conv_fp_#{SecureRandom.hex(8)}"
    @test_ip = "192.168.#{rand(1..254)}.#{rand(1..254)}"
    @test_user_agent = "TestAgent/#{SecureRandom.hex(4)}"
    @device_fingerprint = "fp_conv_#{SecureRandom.hex(16)}"
  end

  def teardown
    VerificationHelper.cleanup(visitor_id: @visitor_id)
  rescue StandardError
    nil
  end

  # Main test: Conversion with fingerprint fallback when visitor_id not found
  # NOTE: This tests a fingerprint fallback feature where conversions with unknown
  # visitor_id are matched to visitors via ip+user_agent. Feature not yet implemented.
  def test_conversion_with_fingerprint_fallback
    skip "Fingerprint fallback feature not implemented"
    skip "Requires local API server" unless api_available?

    # Step 1: Create session first (creates visitor) - required per require_existing_visitor spec
    session_result = create_session(
      visitor_id: @visitor_id,
      session_id: @session_id,
      device_fingerprint: @device_fingerprint,
      url: "https://example.com/test"
    )
    assert_equal "accepted", session_result["status"], "Session should be created"

    # Step 2: Track event with specific fingerprint
    event_result = track_event(
      visitor_id: @visitor_id,
      event_type: "page_view",
      ip: @test_ip,
      user_agent: @test_user_agent
    )
    assert_equal 1, event_result["accepted"], "Event should be accepted"

    sleep 1 # Allow processing

    # Step 3: Track conversion with WRONG visitor_id but MATCHING fingerprint
    # The visitor_id doesn't exist, but ip+user_agent match the session
    conversion_result = track_conversion(
      visitor_id: "vis_nonexistent_#{SecureRandom.hex(8)}", # Wrong visitor_id
      conversion_type: "purchase",
      revenue: 99.99,
      ip: @test_ip,
      user_agent: @test_user_agent
    )

    # Should succeed because fingerprint matches recent session
    assert conversion_result["conversion"],
      "Conversion should succeed via fingerprint fallback. Error: #{conversion_result['errors']&.join(', ')}"
    assert conversion_result.dig("conversion", "id"), "Should return conversion id"

    sleep 1

    # Step 4: Verify conversion is linked to correct visitor
    verification = VerificationHelper.verify(visitor_id: @visitor_id)
    assert verification[:conversions]&.any?, "Visitor should have conversion"

    conversion = verification[:conversions].first
    assert_equal "purchase", conversion[:conversion_type]
    assert_equal 99.99, conversion[:revenue].to_f
  end

  # Test: Conversion fails when no fingerprint match and visitor_id not found
  def test_conversion_fails_without_matching_fingerprint
    skip "Requires local API server" unless api_available?

    # Try to track conversion with non-existent visitor and no fingerprint context
    conversion_result = track_conversion(
      visitor_id: "vis_totally_fake_#{SecureRandom.hex(8)}",
      conversion_type: "signup",
      revenue: 0
      # No ip/user_agent - can't do fingerprint lookup
    )

    refute conversion_result["success"], "Conversion should fail without visitor"
    assert conversion_result["errors"]&.include?("Visitor not found"),
      "Should return 'Visitor not found' error"
  end

  # Test: Event-based conversion still works (takes precedence)
  def test_event_based_conversion_takes_precedence
    skip "Requires local API server" unless api_available?

    # Create session first (creates visitor) - required per require_existing_visitor spec
    session_result = create_session(
      visitor_id: @visitor_id,
      session_id: @session_id,
      device_fingerprint: @device_fingerprint,
      url: "https://example.com/cart"
    )
    assert_equal "accepted", session_result["status"], "Session should be created"

    # Create event
    event_result = track_event(
      visitor_id: @visitor_id,
      event_type: "add_to_cart",
      ip: @test_ip,
      user_agent: @test_user_agent
    )
    assert_equal 1, event_result["accepted"]

    sleep 1

    verification = VerificationHelper.verify(visitor_id: @visitor_id)
    event_id = verification[:events]&.first&.dig(:id)
    skip "Could not get event_id" unless event_id

    # Track conversion with event_id (should use event's visitor, ignore fingerprint)
    conversion_result = track_conversion_with_event(
      event_id: event_id,
      conversion_type: "purchase",
      revenue: 50.00
    )

    assert conversion_result["success"], "Event-based conversion should succeed"
  end

  private

  def api_available?
    HTTParty.get("#{TestConfig.api_url}/health")
    true
  rescue StandardError
    false
  end

  def track_event(visitor_id:, event_type:, ip:, user_agent:)
    HTTParty.post(
      "#{TestConfig.api_url}/events",
      headers: auth_headers,
      body: {
        events: [{
          visitor_id: visitor_id,
          event_type: event_type,
          ip: ip,
          user_agent: user_agent,
          properties: { url: "https://example.com/test" }
        }]
      }.to_json
    ).parsed_response
  rescue StandardError => e
    { "accepted" => 0, "error" => e.message }
  end

  def track_conversion(visitor_id:, conversion_type:, revenue:, ip: nil, user_agent: nil)
    body = {
      conversion: {
        visitor_id: visitor_id,
        conversion_type: conversion_type,
        revenue: revenue
      }
    }
    body[:conversion][:ip] = ip if ip
    body[:conversion][:user_agent] = user_agent if user_agent

    HTTParty.post(
      "#{TestConfig.api_url}/conversions",
      headers: auth_headers,
      body: body.to_json
    ).parsed_response
  rescue StandardError => e
    { "success" => false, "errors" => [e.message] }
  end

  def track_conversion_with_event(event_id:, conversion_type:, revenue:)
    HTTParty.post(
      "#{TestConfig.api_url}/conversions",
      headers: auth_headers,
      body: {
        conversion: {
          event_id: event_id,
          conversion_type: conversion_type,
          revenue: revenue
        }
      }.to_json
    ).parsed_response
  rescue StandardError => e
    { "success" => false, "errors" => [e.message] }
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

  def auth_headers
    {
      "Authorization" => "Bearer #{TestConfig.api_key}",
      "Content-Type" => "application/json"
    }
  end
end
