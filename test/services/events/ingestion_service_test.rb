require "test_helper"

class Events::IngestionServiceTest < ActiveSupport::TestCase
  test "should accept all valid events" do
    assert_difference -> { Event.count }, 2 do
      assert_equal 2, result[:accepted]
      assert_empty result[:rejected]
    end
  end

  test "should reject invalid events" do
    @events_data = [
      valid_event_data,
      invalid_event_data
    ]

    assert_difference -> { Event.count }, 1 do
      assert_equal 1, result[:accepted]
      assert_equal 1, result[:rejected].size
    end
  end

  test "should include error details for rejected events" do
    @events_data = [invalid_event_data]

    rejected = result[:rejected].first
    assert_equal 0, rejected[:index]
    assert rejected[:errors].present?
  end

  test "should handle empty events array" do
    @events_data = []

    assert_equal 0, result[:accepted]
    assert_empty result[:rejected]
  end

  test "should handle all invalid events" do
    @events_data = [
      invalid_event_data,
      { "event_type" => "page_view" }
    ]

    assert_no_difference -> { Event.count } do
      assert_equal 0, result[:accepted]
      assert_equal 2, result[:rejected].size
    end
  end

  test "should validate before processing" do
    @events_data = [
      valid_event_data.except("visitor_id")
    ]

    assert_no_difference -> { Event.count } do
      assert_equal 0, result[:accepted]
      assert_equal 1, result[:rejected].size
    end
  end

  private

  def result
    @result ||= service.call(events_data)
  end

  def service
    @service ||= Events::IngestionService.new(account)
  end

  def events_data
    @events_data ||= [
      valid_event_data,
      valid_event_data.merge("visitor_id" => "vis_different", "session_id" => "sess_different")
    ]
  end

  def valid_event_data
    {
      "event_type" => "page_view",
      "visitor_id" => visitor.visitor_id,
      "session_id" => session.session_id,
      "timestamp" => "2025-11-07T10:30:45Z",
      "properties" => {
        "url" => "https://example.com/page"
      }
    }
  end

  def invalid_event_data
    { "event_type" => "" }
  end

  def account
    @account ||= accounts(:one)
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def session
    @session ||= sessions(:one)
  end
end
