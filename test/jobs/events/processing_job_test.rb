# frozen_string_literal: true

require "test_helper"

class Events::ProcessingJobTest < ActiveJob::TestCase
  test "should process event successfully" do
    assert_difference -> { Event.count }, 1 do
      Events::ProcessingJob.perform_now(account.id, event_data)
    end
  end

  test "should create event with correct data" do
    Events::ProcessingJob.perform_now(account.id, event_data)

    event = Event.last

    assert_equal "page_view", event.event_type
    assert_equal account, event.account
    assert_equal visitor.visitor_id, event.visitor.visitor_id
  end

  test "should handle processing errors gracefully" do
    invalid_data = event_data.merge("event_type" => "")

    assert_no_difference -> { Event.count } do
      Events::ProcessingJob.perform_now(account.id, invalid_data)
    end
  end

  test "should find account by id" do
    Events::ProcessingJob.perform_now(account.id, event_data)

    event = Event.last

    assert_equal account, event.account
  end

  test "should reject event with unknown visitor_id" do
    data = event_data.merge("visitor_id" => "vis_unknown_123")

    assert_no_difference -> { Event.count } do
      Events::ProcessingJob.perform_now(account.id, data)
    end
  end

  test "should create session for existing visitor" do
    assert_difference -> { Session.count }, 1 do
      Events::ProcessingJob.perform_now(account.id, event_data)
    end
  end

  private

  def account
    @account ||= accounts(:one)
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def event_data
    {
      "event_type" => "page_view",
      "visitor_id" => visitor.visitor_id,
      "session_id" => "sess_test_#{SecureRandom.hex(8)}",
      "timestamp" => "2025-11-07T10:30:45Z",
      "properties" => {
        "url" => "https://example.com/page",
        "utm_source" => "google"
      }
    }
  end
end
