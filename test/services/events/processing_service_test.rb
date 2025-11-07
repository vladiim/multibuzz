require "test_helper"

class Events::ProcessingServiceTest < ActiveSupport::TestCase
  test "should create event with valid data" do
    assert_difference -> { Event.count }, 1 do
      assert result[:success]
      assert result[:event].persisted?
      assert_equal "page_view", result[:event].event_type
    end
  end

  test "should associate event with account" do
    assert_equal account, result[:event].account
  end

  test "should find or create visitor" do
    @visitor_id = "vis_new_visitor"
    @session_id = "sess_new_session_for_visitor"

    assert_difference -> { Visitor.count }, 1 do
      assert result[:success]
      assert_equal "vis_new_visitor", result[:event].visitor.visitor_id
    end
  end

  test "should use existing visitor" do
    assert_no_difference -> { Visitor.count } do
      assert result[:success]
      assert_equal visitor, result[:event].visitor
    end
  end

  test "should find or create session" do
    @session_id = "sess_new_session"

    assert_difference -> { Session.count }, 1 do
      assert result[:success]
      assert_equal "sess_new_session", result[:event].session.session_id
    end
  end

  test "should use existing session" do
    assert_no_difference -> { Session.count } do
      assert result[:success]
      assert_equal session, result[:event].session
    end
  end

  test "should parse ISO8601 timestamp" do
    @event_data = valid_event_data.merge("timestamp" => "2025-11-07T15:30:00Z")

    assert result[:success]
    assert_equal Time.iso8601("2025-11-07T15:30:00Z"), result[:event].occurred_at
  end

  test "should store properties as JSONB" do
    assert result[:success]
    assert_equal "https://example.com/page", result[:event].properties["url"]
    assert_equal "google", result[:event].properties["utm_source"]
  end

  test "should capture UTM parameters in session on first event" do
    @session_id = "sess_brand_new"

    assert result[:success]
    assert_equal "google", result[:event].session.initial_utm["utm_source"]
    assert_equal "cpc", result[:event].session.initial_utm["utm_medium"]
  end

  test "should not override session UTM on subsequent events" do
    existing_session = sessions(:one)
    @session_id = existing_session.session_id
    @event_data = valid_event_data.merge(
      "properties" => { "utm_source" => "facebook" }
    )

    assert result[:success]
    assert_equal "google", result[:event].session.initial_utm["utm_source"]
  end

  test "should return error if event fails to save" do
    @event_data = valid_event_data.merge("event_type" => "")

    assert_not result[:success]
    assert result[:errors].present?
  end

  private

  def result
    @result ||= service.call
  end

  def service
    @service ||= Events::ProcessingService.new(account, event_data)
  end

  def event_data
    @event_data ||= valid_event_data
  end

  def valid_event_data
    {
      "event_type" => "page_view",
      "visitor_id" => visitor_id,
      "session_id" => session_id,
      "timestamp" => "2025-11-07T10:30:45Z",
      "properties" => {
        "url" => "https://example.com/page",
        "utm_source" => "google",
        "utm_medium" => "cpc"
      }
    }
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

  def visitor_id
    @visitor_id ||= visitor.visitor_id
  end

  def session_id
    @session_id ||= session.session_id
  end
end
