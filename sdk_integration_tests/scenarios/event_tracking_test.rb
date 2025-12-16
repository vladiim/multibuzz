# frozen_string_literal: true

require_relative "../test_helper"

class EventTrackingTest < SdkIntegrationTest
  def test_tracks_event_via_ui
    visit "/"
    track_visitor_id!

    # Fill in the event form using unique IDs
    within("#event-form") do
      fill_in "event-type", with: "test_click"
      fill_in "event-properties", with: '{"button": "signup"}'
      click_button "Track Event"
    end

    # Wait for async event processing
    wait_for_async(3)

    # Verify event in database
    data = verify_test_data
    assert_not_nil data[:events], "Should have events"
    assert data[:events].any? { |e| e[:event_type] == "test_click" },
      "Should have test_click event"

    event = data[:events].find { |e| e[:event_type] == "test_click" }
    assert_equal "signup", event[:properties][:button]
  end

  def test_event_includes_url_property
    visit "/"
    track_visitor_id!

    within("#event-form") do
      fill_in "event-type", with: "page_view"
      fill_in "event-properties", with: '{"custom": "value"}'
      click_button "Track Event"
    end

    wait_for_async(3)

    data = verify_test_data
    event = data[:events].find { |e| e[:event_type] == "page_view" }

    assert_not_nil event, "Should have page_view event"
    # URL should be auto-enriched by the SDK
    url_present = event[:url] && !event[:url].to_s.empty?
    props_url_present = event[:properties] && event[:properties][:url] && !event[:properties][:url].to_s.empty?
    assert url_present || props_url_present, "Event should have URL property"
  end

  def test_tracks_multiple_events
    visit "/"
    track_visitor_id!

    within("#event-form") do
      # Track first event
      fill_in "event-type", with: "event_one"
      click_button "Track Event"

      # Track second event
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
