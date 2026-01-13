# frozen_string_literal: true

require_relative "../test_helper"

class UtmCaptureTest < SdkIntegrationTest
  def test_captures_utm_params_on_first_visit
    # Visit with UTM parameters
    visit "/?utm_source=google&utm_medium=cpc&utm_campaign=test_campaign"
    track_visitor_id!

    # Create session with UTM URL
    result = create_session_for_visitor(
      @visitor_id,
      url: "#{sdk_app_url}/?utm_source=google&utm_medium=cpc&utm_campaign=test_campaign"
    )
    assert_equal "accepted", result["status"], "Session creation should succeed"

    wait_for_async(2)

    data = verify_test_data
    session = data[:sessions].first
    assert_not_nil session, "Should have a session"

    utm = session[:initial_utm]
    assert_not_nil utm, "Session should have initial_utm"
    assert_equal "google", utm[:utm_source]
    assert_equal "cpc", utm[:utm_medium]
    assert_equal "test_campaign", utm[:utm_campaign]
  end

  def test_captures_referrer
    # Visit page
    visit "/"
    track_visitor_id!

    # Create session with referrer
    result = create_session_for_visitor(
      @visitor_id,
      url: "#{sdk_app_url}/",
      referrer: "https://google.com/search?q=test"
    )
    assert_equal "accepted", result["status"], "Session creation should succeed"

    wait_for_async(2)

    data = verify_test_data
    session = data[:sessions].first

    # Referrer should be captured
    assert session.key?(:initial_referrer), "Session should have referrer field"
    assert_equal "https://google.com/search?q=test", session[:initial_referrer]
  end

  def test_utm_persists_in_session
    # First visit with UTM
    visit "/?utm_source=facebook&utm_medium=social"
    track_visitor_id!

    # Create session with UTM
    result = create_session_for_visitor(
      @visitor_id,
      url: "#{sdk_app_url}/?utm_source=facebook&utm_medium=social"
    )
    session_id = result["session_id"]

    wait_for_async(2)

    # Verify UTM was captured
    data = verify_test_data
    session = data[:sessions].find { |s| s[:session_id] == session_id }
    assert_not_nil session, "Should find session"
    assert_equal "facebook", session[:initial_utm][:utm_source]
    assert_equal "social", session[:initial_utm][:utm_medium]
  end

  def test_channel_derived_from_utm
    # Visit with UTM indicating paid search
    visit "/?utm_source=google&utm_medium=cpc"
    track_visitor_id!

    # Create session
    result = create_session_for_visitor(
      @visitor_id,
      url: "#{sdk_app_url}/?utm_source=google&utm_medium=cpc"
    )
    assert_equal "accepted", result["status"]

    wait_for_async(2)

    data = verify_test_data
    session = data[:sessions].first

    # Channel should be derived from UTM
    assert_not_nil session[:channel], "Session should have channel"
    assert_equal "paid_search", session[:channel]
  end
end
