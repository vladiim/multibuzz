# frozen_string_literal: true

require_relative "../test_helper"

# Tests that the sGTM simulation app persists visitor IDs across requests,
# simulating server-set first-party cookies.
class SgtmVisitorPersistenceTest < SdkIntegrationTest
  def test_visitor_id_persists_across_page_loads
    visit "/"
    track_visitor_id!
    first_visitor_id = @visitor_id

    visit "/"
    second_visitor_id = current_visitor_id

    assert_equal first_visitor_id, second_visitor_id, "Visitor ID should persist"
  end

  def test_registered_visitor_persists
    visit "/"
    track_visitor_id!
    first_visitor_id = @visitor_id
    create_session_for_visitor(@visitor_id)

    visit "/"
    second_visitor_id = current_visitor_id

    assert_equal first_visitor_id, second_visitor_id, "Registered visitor should persist"

    wait_for_async(1)
    data = verify_test_data
    assert data[:visitor], "Visitor should exist in API"
  end
end
