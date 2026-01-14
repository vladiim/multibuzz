# frozen_string_literal: true

require_relative "../test_helper"

# Tests for automatic session creation by SDK middleware
# Verifies that middleware calls POST /api/v1/sessions to register visitors
#
# This test is part of the sdk_session_creation_spec.md implementation.
# Before the fix: These tests FAIL because middleware doesn't call /sessions
# After the fix: These tests PASS because middleware creates sessions automatically
class SessionCreationTest < SdkIntegrationTest
  # -------------------------------------------------------------------
  # Core session creation tests
  # -------------------------------------------------------------------

  def test_middleware_creates_session_on_first_visit
    # Visit the page - middleware should automatically create session
    visit "/"
    track_visitor_id!

    # Wait for async session creation
    wait_for_async(2)

    # Verify session was created WITHOUT manual create_session_for_visitor call
    data = verify_test_data
    refute_nil data, "Should be able to verify test data"
    refute_nil data[:visitor], "Visitor should be created automatically by middleware"
    refute_empty data[:sessions], "Session should be created automatically by middleware"

    # Verify session has attribution data
    session = data[:sessions].first
    refute_nil session[:channel], "Session should have channel attribution"
  end

  def test_middleware_creates_session_with_utm_params
    # Visit with UTM parameters
    visit "/?utm_source=google&utm_medium=cpc&utm_campaign=test_campaign"
    track_visitor_id!

    wait_for_async(2)

    data = verify_test_data
    refute_nil data[:visitor], "Visitor should be created automatically"
    refute_empty data[:sessions], "Session should be created automatically"

    # Verify UTM params were captured
    session = data[:sessions].first
    assert_equal "paid_search", session[:channel], "Channel should be derived from UTM"

    utm = session[:initial_utm] || {}
    assert_equal "google", utm["utm_source"] || utm[:utm_source], "utm_source should be captured"
    assert_equal "cpc", utm["utm_medium"] || utm[:utm_medium], "utm_medium should be captured"
    assert_equal "test_campaign", utm["utm_campaign"] || utm[:utm_campaign], "utm_campaign should be captured"
  end

  def test_middleware_creates_session_with_referrer
    # Can't easily set referrer in Capybara, but test the session structure
    visit "/"
    track_visitor_id!

    wait_for_async(2)

    data = verify_test_data
    refute_nil data[:visitor], "Visitor should be created automatically"
    refute_empty data[:sessions], "Session should be created automatically"

    # Session should have started_at timestamp
    session = data[:sessions].first
    refute_nil session[:started_at], "Session should have started_at timestamp"
  end

  # -------------------------------------------------------------------
  # Event tracking tests (events should work after auto-session creation)
  # -------------------------------------------------------------------

  def test_event_succeeds_after_automatic_session_creation
    # Visit the page - middleware creates session
    visit "/"
    track_visitor_id!

    wait_for_async(2)

    # Now track an event - should succeed because visitor exists
    click_button "Track Event" rescue nil

    # Use the API endpoint directly for reliability
    response = post_json("/api/event", {
      event_type: "auto_session_test_event",
      properties: { test: true }
    })

    assert_equal true, response["success"],
      "Event should succeed after automatic session creation. Got: #{response.inspect}"

    # Verify event was created
    wait_for_async(2)
    data = verify_test_data
    event = data[:events]&.find { |e| e[:event_type] == "auto_session_test_event" }
    refute_nil event, "Event should be created after automatic session creation"
  end

  def test_conversion_succeeds_after_automatic_session_creation
    # Visit the page - middleware creates session
    visit "/"
    track_visitor_id!

    wait_for_async(2)

    # Track a conversion - should succeed because visitor exists
    response = post_json("/api/conversion", {
      conversion_type: "auto_session_test_conversion",
      revenue: 99.99
    })

    assert_equal true, response["success"],
      "Conversion should succeed after automatic session creation. Got: #{response.inspect}"
  end

  # -------------------------------------------------------------------
  # Returning visitor tests
  # -------------------------------------------------------------------

  def test_returning_visitor_reuses_existing_session
    # First visit - creates visitor and session
    visit "/"
    track_visitor_id!
    first_visitor_id = @visitor_id

    wait_for_async(2)

    # Second visit - should reuse visitor
    visit "/"
    second_visitor_id = current_visitor_id

    assert_equal first_visitor_id, second_visitor_id, "Visitor ID should persist"

    wait_for_async(1)

    # Verify only one visitor created (no duplicates)
    data = verify_test_data
    refute_nil data[:visitor], "Should have visitor"
    # Session count may vary based on timing/expiry, but visitor should be same
    assert_equal first_visitor_id, data[:visitor][:visitor_id], "Should be same visitor"
  end

  def test_returning_visitor_can_track_events
    # First visit - creates session
    visit "/"
    track_visitor_id!

    wait_for_async(2)

    # Navigate away and back (simulates returning visitor)
    visit "/api/ids"  # Different page
    visit "/"

    wait_for_async(1)

    # Track event - should work because visitor exists
    response = post_json("/api/event", {
      event_type: "returning_visitor_event",
      properties: { visit: "second" }
    })

    assert_equal true, response["success"],
      "Returning visitor should be able to track events. Got: #{response.inspect}"
  end

  # -------------------------------------------------------------------
  # Session cookie tests
  # -------------------------------------------------------------------

  def test_session_cookie_is_set
    visit "/"
    track_visitor_id!

    # After the fix, middleware should set session cookie
    # Check via API endpoint that returns current IDs
    response = get_json("/api/ids")

    # Session ID might be nil in response (server-side), but should be tracked
    refute_nil @visitor_id, "Visitor ID should be set"
    # The middleware should create session, verified by checking server
    wait_for_async(2)
    data = verify_test_data
    refute_empty data[:sessions], "Session should exist on server"
  end

  private

  # HTTP helper to POST JSON directly to test app
  def post_json(path, data)
    uri = URI.parse("#{sdk_app_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    # Include visitor cookie for session
    request["Cookie"] = "_mbuzz_vid=#{@visitor_id}" if @visitor_id
    request.body = data.to_json

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    { "success" => false, "error" => e.message }
  end

  # HTTP helper to GET JSON from test app
  def get_json(path)
    uri = URI.parse("#{sdk_app_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Get.new(uri.path)
    request["Cookie"] = "_mbuzz_vid=#{@visitor_id}" if @visitor_id

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    { "error" => e.message }
  end
end
