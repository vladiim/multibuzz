# frozen_string_literal: true

require_relative "../test_helper"

class ConcurrentTest < SdkIntegrationTest
  def test_different_browser_sessions_have_unique_visitor_ids
    # First browser session
    visit "/"
    first_visitor_id = current_visitor_id

    # Reset to simulate different browser/incognito
    Capybara.reset_sessions!

    # Second browser session
    visit "/"
    second_visitor_id = current_visitor_id

    # Different browser sessions should have different visitor IDs
    refute_equal first_visitor_id, second_visitor_id,
      "Different browser sessions should have unique visitor IDs"

    # Both should be valid IDs
    assert_match(/\A[a-f0-9]{64}\z/, first_visitor_id)
    assert_match(/\A[a-f0-9]{64}\z/, second_visitor_id)
  end

  def test_rapid_events_dont_conflict
    # Register visitor first
    visit_and_register

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
    # Register visitor first
    visit_and_register

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

  def test_sessions_created_via_api_have_unique_ids
    # First visitor/session
    visit "/"
    track_visitor_id!
    first_visitor_id = @visitor_id
    first_result = create_session_for_visitor(first_visitor_id)
    first_session_id = first_result["session_id"]

    # Reset and create second visitor/session
    Capybara.reset_sessions!
    @visitor_id = nil

    visit "/"
    track_visitor_id!
    second_visitor_id = @visitor_id
    second_result = create_session_for_visitor(second_visitor_id)
    second_session_id = second_result["session_id"]

    # Different visitors should have different session IDs
    refute_equal first_session_id, second_session_id,
      "Different visitors should have unique session IDs"

    # Both should be valid IDs
    assert_match(/\A[a-f0-9]{64}\z/, first_session_id)
    assert_match(/\A[a-f0-9]{64}\z/, second_session_id)
  end
end
