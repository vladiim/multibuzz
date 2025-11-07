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
    assert_equal "vis_test_123", event.visitor.visitor_id
    assert_equal "sess_test_456", event.session.session_id
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

  test "should create visitor if not exists" do
    data = event_data.merge("visitor_id" => "vis_new_123", "session_id" => "sess_new_456")

    assert_difference -> { Visitor.count }, 1 do
      Events::ProcessingJob.perform_now(account.id, data)
    end
  end

  test "should create session if not exists" do
    data = event_data.merge("visitor_id" => "vis_new_123", "session_id" => "sess_new_456")

    assert_difference -> { Session.count }, 1 do
      Events::ProcessingJob.perform_now(account.id, data)
    end
  end

  private

  def account
    @account ||= accounts(:one)
  end

  def event_data
    {
      "event_type" => "page_view",
      "visitor_id" => "vis_test_123",
      "session_id" => "sess_test_456",
      "timestamp" => "2025-11-07T10:30:45Z",
      "properties" => {
        "url" => "https://example.com/page",
        "utm_source" => "google"
      }
    }
  end
end
