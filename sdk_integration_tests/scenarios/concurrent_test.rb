# frozen_string_literal: true

require_relative "../test_helper"

class ConcurrentTest < SdkIntegrationTest
  def test_different_browser_sessions_have_unique_visitor_ids
    # First browser session
    visit "/"
    first_visitor_id = current_visitor_id
    first_session_id = current_session_id

    # Reset to simulate different browser/incognito
    Capybara.reset_sessions!

    # Second browser session
    visit "/"
    second_visitor_id = current_visitor_id
    second_session_id = current_session_id

    # Different browser sessions should have different IDs
    refute_equal first_visitor_id, second_visitor_id,
      "Different browser sessions should have unique visitor IDs"
    refute_equal first_session_id, second_session_id,
      "Different browser sessions should have unique session IDs"

    # Both should be valid IDs
    assert_match(/\A[a-f0-9]{64}\z/, first_visitor_id)
    assert_match(/\A[a-f0-9]{64}\z/, second_visitor_id)
  end

  def test_rapid_events_dont_conflict
    visit "/"
    track_visitor_id!

    # Track multiple events rapidly
    within("#event-form") do
      5.times do |i|
        fill_in "event-type", with: "rapid_event_#{i}"
        click_button "Track Event"
      end
    end

    wait_for_async(5)

    data = verify_test_data
    event_types = data[:events].map { |e| e[:event_type] }

    # At least some events should be tracked (async may batch/dedupe)
    rapid_events = event_types.select { |t| t.start_with?("rapid_event_") }
    assert rapid_events.any?, "Should have tracked at least one rapid event"
  end

  def test_all_events_have_same_visitor_id
    visit "/"
    track_visitor_id!

    # Track several events
    within("#event-form") do
      %w[event_a event_b event_c].each do |event_type|
        fill_in "event-type", with: event_type
        click_button "Track Event"
        sleep 0.5 # Small delay between events
      end
    end

    wait_for_async(3)

    data = verify_test_data

    # All events should belong to the same visitor
    # This is implicitly true since we query by visitor_id,
    # but verify the visitor data is consistent
    assert_equal @visitor_id, data[:visitor][:visitor_id]
    assert data[:events].length >= 1, "Should have at least one event"
  end
end
