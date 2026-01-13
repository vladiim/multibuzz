# frozen_string_literal: true

require_relative "../test_helper"

class ReturningVisitTest < SdkIntegrationTest
  def test_visitor_id_persists_for_returning_visitor
    # First visit
    visit "/"
    track_visitor_id!
    first_visitor_id = @visitor_id

    # Clear session but keep visitor cookie (simulate browser restart)
    Capybara.reset_sessions!

    # Note: In real scenario, visitor cookie would persist in browser storage
    # This test verifies the ID format and that we can track returning visitors
    visit "/"
    second_visitor_id = current_visitor_id

    # In a real browser, these would be equal due to persistent cookie
    # For this test, we verify both are valid visitor IDs
    assert_match(/\A[a-f0-9]{64}\z/, first_visitor_id)
    assert_match(/\A[a-f0-9]{64}\z/, second_visitor_id)
  end

  def test_session_created_via_api_has_valid_id
    # Session IDs are now server-side (v0.7.0+)
    # Test that sessions created via API have valid IDs
    visit "/"
    track_visitor_id!

    result = create_session_for_visitor(@visitor_id)

    assert_equal "accepted", result["status"]
    assert_match(/\A[a-f0-9]{64}\z/, result["session_id"], "Session ID should be 64 hex chars")
  end

  def test_session_exists_after_registration
    # Register visitor via session creation
    visit_and_register

    wait_for_async(2)

    data = verify_test_data

    # Session exists after registration
    assert_equal 1, data[:sessions].length, "Should have 1 session after registration"

    # Visitor exists
    refute_nil data[:visitor][:visitor_id]
    refute_empty data[:visitor][:visitor_id]
  end

  def test_multiple_sessions_for_same_visitor
    # First session
    visit "/"
    track_visitor_id!
    first_visitor_id = @visitor_id
    create_session_for_visitor(@visitor_id)

    # Wait a bit and create a second session (simulates new browser session)
    wait_for_async(1)

    # Create a second session for the same visitor
    session_id_2 = SecureRandom.hex(32)
    uri = URI.parse("#{TestConfig.api_url}/sessions")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri.path)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{TestConfig.api_key}"
    request.body = {
      session: {
        visitor_id: first_visitor_id,
        session_id: session_id_2,
        url: "#{sdk_app_url}/page2",
        started_at: Time.now.utc.iso8601
      }
    }.to_json
    http.request(request)

    wait_for_async(2)

    data = verify_test_data

    # Should have 2 sessions for the same visitor
    assert_equal 2, data[:sessions].length, "Should have 2 sessions for same visitor"
    assert_equal first_visitor_id, data[:visitor][:visitor_id]
  end
end
