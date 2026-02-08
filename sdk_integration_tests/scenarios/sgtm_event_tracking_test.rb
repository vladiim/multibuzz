# frozen_string_literal: true

require_relative "../test_helper"

# Tests that the sGTM simulation app tracks events correctly
# by making direct HTTP calls to the mbuzz events API.
class SgtmEventTrackingTest < SdkIntegrationTest
  def test_tracks_event_via_ui
    visit_and_register

    within("#event-form") do
      fill_in "event-type", with: "test_click"
      fill_in "event-properties", with: '{"button": "signup"}'
      click_button "Track Event"
    end

    wait_for_async(3)

    data = verify_test_data
    assert_not_nil data[:events], "Should have events"
    assert data[:events].any? { |e| e[:event_type] == "test_click" },
      "Should have test_click event"

    event = data[:events].find { |e| e[:event_type] == "test_click" }
    assert_equal "signup", event[:properties][:button]
  end

  def test_tracks_multiple_events
    visit_and_register

    within("#event-form") do
      fill_in "event-type", with: "event_one"
      click_button "Track Event"

      fill_in "event-type", with: "event_two"
      click_button "Track Event"
    end

    wait_for_async(3)

    data = verify_test_data
    event_types = data[:events].map { |e| e[:event_type] }

    assert_includes event_types, "event_one"
    assert_includes event_types, "event_two"
  end
end
