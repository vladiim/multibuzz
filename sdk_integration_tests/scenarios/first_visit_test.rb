# frozen_string_literal: true

require_relative "../test_helper"

class FirstVisitTest < SdkIntegrationTest
  def test_creates_visitor_id_on_first_visit
    visit "/"
    track_visitor_id!

    assert_match(/\A[a-f0-9]{64}\z/, @visitor_id, "Visitor ID should be 64 hex chars")
  end

  def test_session_created_via_api
    # Session IDs are now server-side (v0.7.0+), not exposed to client
    # Test that we can create a session via the API
    visit "/"
    track_visitor_id!

    result = create_session_for_visitor(@visitor_id)

    assert_equal "accepted", result["status"], "Session should be created via API"
    assert_match(/\A[a-f0-9]{64}\z/, result["session_id"], "Session ID should be 64 hex chars")
  end

  def test_visitor_id_persists_across_page_loads
    visit "/"
    track_visitor_id!
    first_visitor_id = @visitor_id

    # Navigate away and back
    visit "/"
    second_visitor_id = current_visitor_id

    assert_equal first_visitor_id, second_visitor_id, "Visitor ID should persist"
  end

  def test_visitor_registered_via_session_persists
    # First visit - create visitor via session
    visit "/"
    track_visitor_id!
    first_visitor_id = @visitor_id
    create_session_for_visitor(@visitor_id)

    # Second visit - same visitor
    visit "/"
    second_visitor_id = current_visitor_id

    assert_equal first_visitor_id, second_visitor_id, "Registered visitor should persist"

    # Verify visitor exists in API
    wait_for_async(1)
    data = verify_test_data

    assert data[:visitor], "Visitor should exist in API"
  end
end
