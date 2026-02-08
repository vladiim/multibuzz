# frozen_string_literal: true

require_relative "../test_helper"

# Tests that the sGTM simulation app creates sessions correctly.
# The sGTM test app makes direct HTTP calls to the mbuzz API,
# simulating what an sGTM tag template would do.
class SgtmSessionCreationTest < SdkIntegrationTest
  def test_creates_visitor_on_first_visit
    visit "/"
    track_visitor_id!

    assert_match(/\A[a-f0-9]{64}\z/, @visitor_id, "Visitor ID should be 64 hex chars")
  end

  def test_creates_session_via_direct_api_call
    visit "/"
    track_visitor_id!

    result = create_session_for_visitor(@visitor_id)

    assert_equal "accepted", result["status"], "Session should be created via API"
    assert_match(/\A[a-f0-9]{64}\z/, result["session_id"], "Session ID should be 64 hex chars")
  end

  def test_session_captures_url
    visit "/"
    track_visitor_id!

    url = "#{sdk_app_url}/landing?utm_source=google&utm_medium=cpc"
    result = create_session_for_visitor(@visitor_id, url: url)
    assert_equal "accepted", result["status"]

    wait_for_async(2)

    data = verify_test_data
    session = data[:sessions].first
    assert_not_nil session, "Should have a session"
    assert_equal "google", session[:initial_utm][:utm_source]
    assert_equal "cpc", session[:initial_utm][:utm_medium]
  end

  def test_session_captures_referrer
    visit "/"
    track_visitor_id!

    result = create_session_for_visitor(
      @visitor_id,
      url: "#{sdk_app_url}/",
      referrer: "https://google.com/search?q=test"
    )
    assert_equal "accepted", result["status"]

    wait_for_async(2)

    data = verify_test_data
    session = data[:sessions].first
    assert session.key?(:initial_referrer), "Session should have referrer field"
    assert_equal "https://google.com/search?q=test", session[:initial_referrer]
  end
end
