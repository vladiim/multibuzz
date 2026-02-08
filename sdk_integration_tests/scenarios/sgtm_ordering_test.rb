# frozen_string_literal: true

require_relative "../test_helper"

# Tests the critical ordering constraint: visitors must be created
# via session creation BEFORE events can be tracked. This mirrors
# the require_existing_visitor enforcement in production.
class SgtmOrderingTest < SdkIntegrationTest
  def test_events_succeed_after_session_creation
    visit_and_register

    within("#event-form") do
      fill_in "event-type", with: "after_session"
      click_button "Track Event"
    end

    wait_for_async(3)

    data = verify_test_data
    assert data[:events].any? { |e| e[:event_type] == "after_session" },
      "Event should succeed after session creation"
  end
end
