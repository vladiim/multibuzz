require "test_helper"

class Events::ValidationServiceTest < ActiveSupport::TestCase
  test "should validate complete event" do
    assert result[:valid]
    assert_empty result[:errors]
  end

  test "should require event_type" do
    @event_data = valid_event_data.except("event_type")

    assert_not result[:valid]
    assert_includes result[:errors], "event_type is required"
  end

  test "should require visitor_id" do
    @event_data = valid_event_data.except("visitor_id")

    assert_not result[:valid]
    assert_includes result[:errors], "visitor_id is required"
  end

  test "should require session_id" do
    @event_data = valid_event_data.except("session_id")

    assert_not result[:valid]
    assert_includes result[:errors], "session_id is required"
  end

  test "should require timestamp" do
    @event_data = valid_event_data.except("timestamp")

    assert_not result[:valid]
    assert_includes result[:errors], "timestamp is required"
  end

  test "should require properties" do
    @event_data = valid_event_data.except("properties")

    assert_not result[:valid]
    assert_includes result[:errors], "properties is required"
  end

  test "should validate timestamp is a valid ISO8601 string" do
    @event_data = valid_event_data.merge("timestamp" => "not a timestamp")

    assert_not result[:valid]
    assert_includes result[:errors], "timestamp must be a valid ISO8601 datetime"
  end

  test "should validate properties is a hash" do
    @event_data = valid_event_data.merge("properties" => "not a hash")

    assert_not result[:valid]
    assert_includes result[:errors], "properties must be a hash"
  end

  test "should collect multiple errors" do
    @event_data = { "event_type" => "page_view" }

    assert_not result[:valid]
    assert_includes result[:errors], "visitor_id is required"
    assert_includes result[:errors], "session_id is required"
    assert_includes result[:errors], "timestamp is required"
    assert_includes result[:errors], "properties is required"
  end

  test "should allow valid ISO8601 timestamp" do
    @event_data = valid_event_data.merge("timestamp" => "2025-11-07T10:30:00Z")

    assert result[:valid]
  end

  test "should allow empty properties hash" do
    @event_data = valid_event_data.merge("properties" => {})

    assert result[:valid]
  end

  private

  def result
    @result ||= service.call(event_data)
  end

  def service
    @service ||= Events::ValidationService.new
  end

  def event_data
    @event_data ||= valid_event_data
  end

  def valid_event_data
    {
      "event_type" => "page_view",
      "visitor_id" => "vis_abc123",
      "session_id" => "sess_xyz789",
      "timestamp" => "2025-11-07T10:30:45Z",
      "properties" => {
        "url" => "https://example.com/page",
        "utm_source" => "google"
      }
    }
  end
end
