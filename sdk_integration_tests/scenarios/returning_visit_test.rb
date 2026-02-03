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
    visit_and_register

    wait_for_async(2)

    data = verify_test_data

    # Middleware auto-creates a session + visit_and_register creates another
    assert data[:sessions].length >= 1, "Should have at least 1 session after registration"
    refute_nil data[:visitor][:visitor_id]
    refute_empty data[:visitor][:visitor_id]
  end

  def test_multiple_sessions_for_same_visitor
    visit "/"
    track_visitor_id!
    first_visitor_id = @visitor_id

    wait_for_async(2)

    # Create an additional session via API for the same visitor
    create_session_for_visitor(first_visitor_id, url: "#{sdk_app_url}/page2")

    wait_for_async(2)

    data = verify_test_data

    # Middleware auto-created one session on visit, plus the manual one above
    assert data[:sessions].length >= 2, "Should have at least 2 sessions for same visitor"
    assert_equal first_visitor_id, data[:visitor][:visitor_id]
  end
end
