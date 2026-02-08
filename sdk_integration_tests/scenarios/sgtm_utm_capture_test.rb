# frozen_string_literal: true

require_relative "../test_helper"

# Tests that sessions created via the sGTM simulation correctly
# capture UTM parameters and derive channel attribution.
class SgtmUtmCaptureTest < SdkIntegrationTest
  def test_captures_utm_params_on_session_creation
    visit "/?utm_source=google&utm_medium=cpc&utm_campaign=sgtm_test"
    track_visitor_id!

    result = create_session_for_visitor(
      @visitor_id,
      url: "#{sdk_app_url}/?utm_source=google&utm_medium=cpc&utm_campaign=sgtm_test"
    )
    assert_equal "accepted", result["status"]

    wait_for_async(2)

    data = verify_test_data
    session = data[:sessions].first
    assert_not_nil session, "Should have a session"

    utm = session[:initial_utm]
    assert_equal "google", utm[:utm_source]
    assert_equal "cpc", utm[:utm_medium]
    assert_equal "sgtm_test", utm[:utm_campaign]
  end

  def test_derives_channel_from_utm
    visit "/?utm_source=google&utm_medium=cpc"
    track_visitor_id!

    result = create_session_for_visitor(
      @visitor_id,
      url: "#{sdk_app_url}/?utm_source=google&utm_medium=cpc"
    )
    assert_equal "accepted", result["status"]

    wait_for_async(2)

    data = verify_test_data
    session = data[:sessions].first
    assert_not_nil session[:channel], "Session should have channel"
    assert_equal "paid_search", session[:channel]
  end

  def test_derives_channel_from_referrer
    visit "/"
    track_visitor_id!

    result = create_session_for_visitor(
      @visitor_id,
      url: "#{sdk_app_url}/",
      referrer: "https://www.google.com/search?q=attribution"
    )
    assert_equal "accepted", result["status"]

    wait_for_async(2)

    data = verify_test_data
    session = data[:sessions].first
    assert_not_nil session[:channel], "Session should have channel"
    assert_equal "organic_search", session[:channel]
  end
end
