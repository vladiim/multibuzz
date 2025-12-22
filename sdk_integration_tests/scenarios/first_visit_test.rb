# frozen_string_literal: true

require_relative "../test_helper"

class FirstVisitTest < SdkIntegrationTest
  def test_creates_visitor_id_on_first_visit
    visit "/"

    track_visitor_id!

    assert_match(/\A[a-f0-9]{64}\z/, @visitor_id, "Visitor ID should be 64 hex chars")
  end

  def test_creates_session_id_on_first_visit
    visit "/"

    session_id = current_session_id

    assert_match(/\A[a-f0-9]{64}\z/, session_id, "Session ID should be 64 hex chars")
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

  def test_session_id_persists_within_session_timeout
    visit "/"
    first_session_id = current_session_id

    # Quick reload (within session timeout)
    sleep 1
    visit "/"
    second_session_id = current_session_id

    assert_equal first_session_id, second_session_id, "Session ID should persist within timeout"
  end
end
