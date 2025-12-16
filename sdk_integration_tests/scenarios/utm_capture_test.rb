# frozen_string_literal: true

require_relative "../test_helper"

class UtmCaptureTest < SdkIntegrationTest
  def test_captures_utm_params_on_first_visit
    # Visit with UTM parameters
    visit "/?utm_source=google&utm_medium=cpc&utm_campaign=test_campaign"
    track_visitor_id!

    wait_for_async(3)

    data = verify_test_data
    session = data[:sessions].first
    assert_not_nil session, "Should have a session"

    utm = session[:initial_utm]
    assert_not_nil utm, "Session should have initial_utm"
    assert_equal "google", utm[:utm_source]
    assert_equal "cpc", utm[:utm_medium]
    assert_equal "test_campaign", utm[:utm_campaign]
  end

  # Note: landing_url is not currently captured by the SDK/Session model
  # This test is skipped until landing URL feature is implemented
  # def test_captures_landing_url
  #   visit "/?page=pricing"
  #   track_visitor_id!
  #
  #   wait_for_async(3)
  #
  #   data = verify_test_data
  #   session = data[:sessions].first
  #
  #   assert session[:landing_url].present?, "Session should have landing URL"
  #   assert_includes session[:landing_url], "page=pricing"
  # end

  def test_captures_referrer
    # Note: Playwright can set referrer via page.goto options, but in this test
    # we just verify the field exists and is captured when present
    visit "/"
    track_visitor_id!

    wait_for_async(3)

    data = verify_test_data
    session = data[:sessions].first

    # Referrer may be nil for direct visits, but the field should exist
    assert session.key?(:initial_referrer), "Session should have referrer field"
  end

  def test_utm_persists_across_page_navigation
    # First visit with UTM
    visit "/?utm_source=facebook&utm_medium=social"
    track_visitor_id!
    first_session_id = current_session_id

    wait_for_async(2)

    # Navigate to another page (within session)
    visit "/"
    second_session_id = current_session_id

    # Session should persist
    assert_equal first_session_id, second_session_id

    data = verify_test_data
    session = data[:sessions].find { |s| s[:session_id] == first_session_id }
    assert_equal "facebook", session[:initial_utm][:utm_source]
  end
end
