# frozen_string_literal: true

require_relative "../test_helper"
require "net/http"
require "uri"

# Tests for background job event/conversion tracking
# Verifies that SDK requires explicit visitor_id when called outside request context
class BackgroundJobVisitorTest < SdkIntegrationTest
  # -------------------------------------------------------------------
  # Event tracking tests
  # -------------------------------------------------------------------

  def test_background_event_without_visitor_id_fails
    # Visit the app to get a visitor_id from the cookie
    visit "/"
    track_visitor_id!

    # Create a session to register the visitor in Multibuzz
    session_result = create_session_for_visitor(@visitor_id)
    assert_equal "accepted", session_result["status"],
      "Session creation should succeed. Got: #{session_result.inspect}"

    wait_for_async(1)

    # Now call the background endpoint WITHOUT visitor_id
    # This simulates a background job calling Mbuzz.event() without context
    response = post_json("/api/background_event_no_visitor", {
      event_type: "background_test_no_vid"
    })

    # Should fail - no visitor_id available outside request context
    assert_equal false, response["success"],
      "Background event without visitor_id should fail. Got: #{response.inspect}"
  end

  def test_background_event_with_explicit_visitor_id_succeeds
    # Visit the app to get a visitor_id from the cookie
    visit "/"
    track_visitor_id!
    stored_visitor_id = @visitor_id

    # Verify we have a visitor_id
    assert stored_visitor_id && !stored_visitor_id.empty?, "Should have visitor_id from cookie"

    # Create a session to register the visitor in Multibuzz
    session_result = create_session_for_visitor(stored_visitor_id)
    assert_equal "accepted", session_result["status"],
      "Session creation should succeed. Got: #{session_result.inspect}"

    wait_for_async(1)

    # Call background endpoint WITH explicit visitor_id
    # This is the correct pattern for background jobs
    response = post_json("/api/background_event_with_visitor", {
      event_type: "background_test_with_vid",
      visitor_id: stored_visitor_id,
      properties: { source: "background_job" }
    })

    # Should succeed - explicit visitor_id provided
    assert_equal true, response["success"],
      "Background event with explicit visitor_id should succeed. Got: #{response.inspect}"

    # Verify event was actually created
    wait_for_async(3)
    data = verify_test_data
    event = data[:events]&.find { |e| e[:event_type] == "background_test_with_vid" }

    assert_not_nil event, "Event should be created with explicit visitor_id"
  end

  # -------------------------------------------------------------------
  # Conversion tracking tests
  # -------------------------------------------------------------------

  def test_background_conversion_without_visitor_id_fails
    visit "/"
    track_visitor_id!

    # Create session to register visitor
    session_result = create_session_for_visitor(@visitor_id)
    assert_equal "accepted", session_result["status"],
      "Session creation should succeed. Got: #{session_result.inspect}"

    wait_for_async(1)

    response = post_json("/api/background_conversion_no_visitor", {
      conversion_type: "background_purchase_no_vid",
      revenue: 99.99
    })

    assert_equal false, response["success"],
      "Background conversion without visitor_id should fail. Got: #{response.inspect}"
  end

  def test_background_conversion_with_explicit_visitor_id_succeeds
    visit "/"
    track_visitor_id!
    stored_visitor_id = @visitor_id

    assert stored_visitor_id && !stored_visitor_id.empty?, "Should have visitor_id from cookie"

    # Create session to register visitor
    session_result = create_session_for_visitor(stored_visitor_id)
    assert_equal "accepted", session_result["status"],
      "Session creation should succeed. Got: #{session_result.inspect}"

    wait_for_async(1)

    response = post_json("/api/background_conversion_with_visitor", {
      conversion_type: "background_purchase_with_vid",
      visitor_id: stored_visitor_id,
      revenue: 149.99
    })

    assert_equal true, response["success"],
      "Background conversion with explicit visitor_id should succeed. Got: #{response.inspect}"
  end

  private

  # Create a session via the API to register the visitor
  # Visitors must exist before events can be tracked (require_existing_visitor spec)
  def create_session_for_visitor(visitor_id)
    session_id = SecureRandom.hex(32)
    uri = URI.parse("#{TestConfig.api_url}/sessions")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{TestConfig.api_key}"
    request.body = {
      session: {
        visitor_id: visitor_id,
        session_id: session_id,
        url: "http://localhost:4001/",
        started_at: Time.now.utc.iso8601
      }
    }.to_json

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    { "status" => "error", "error" => e.message }
  end

  # HTTP helper to POST JSON directly to test app (bypasses browser/cookies)
  def post_json(path, data)
    uri = URI.parse("#{sdk_app_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request.body = data.to_json

    response = http.request(request)
    JSON.parse(response.body)
  rescue => e
    { "success" => false, "error" => e.message }
  end
end
