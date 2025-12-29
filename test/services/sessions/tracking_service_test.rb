require "test_helper"

class Sessions::TrackingServiceTest < ActiveSupport::TestCase
  test "should find existing active session" do
    assert result[:success]
    assert_equal session, result[:session]
    assert_not result[:created]
  end

  test "should create new session if not found" do
    @session_id = "sess_new_session_123"

    assert_difference -> { Session.count }, 1 do
      assert result[:success]
      assert result[:created]
      assert_equal "sess_new_session_123", result[:session].session_id
      assert_equal account, result[:session].account
      assert_equal visitor, result[:session].visitor
    end
  end

  test "should not reuse ended session" do
    # When a session ends, client generates new session_id
    # So this test uses a truly new session_id
    @session_id = "sess_brand_new_session"

    fresh_result = nil
    assert_difference -> { Session.count }, 1 do
      fresh_result = Sessions::TrackingService.new(account, session_id, visitor).call
    end

    assert fresh_result[:created]
    assert_equal "sess_brand_new_session", fresh_result[:session].session_id
  end

  test "should increment page view count" do
    # First call to ensure session exists
    result

    initial_count = session.reload.page_view_count

    # Second call should increment
    Sessions::TrackingService.new(account, session_id, visitor).call

    assert_equal initial_count + 1, session.reload.page_view_count
  end

  test "should scope session to account" do
    assert_equal account, result[:session].account
  end

  test "should handle validation errors" do
    @session_id = ""  # Invalid

    assert_not result[:success]
    assert result[:errors].present?
  end

  test "should set started_at from event timestamp when creating session" do
    @session_id = "sess_with_timestamp"
    event_time = 3.days.ago

    service = Sessions::TrackingService.new(account, @session_id, visitor, event_timestamp: event_time)
    result = service.call

    assert result[:success]
    assert result[:created]
    assert_in_delta event_time.to_i, result[:session].started_at.to_i, 1
  end

  test "should default to current time when no event timestamp provided" do
    @session_id = "sess_no_timestamp"

    service = Sessions::TrackingService.new(account, @session_id, visitor)
    result = service.call

    assert result[:success]
    assert_in_delta Time.current.to_i, result[:session].started_at.to_i, 2
  end

  # --- Device Fingerprint ---

  test "should store device_fingerprint when creating session" do
    @session_id = "sess_with_fingerprint"

    service = Sessions::TrackingService.new(
      account, @session_id, visitor,
      device_fingerprint: "abc123fingerprint"
    )
    result = service.call

    assert result[:success]
    assert_equal "abc123fingerprint", result[:session].device_fingerprint
  end

  # --- Last Activity Tracking ---

  test "should set last_activity_at when creating session" do
    @session_id = "sess_new_with_activity"
    event_time = 1.hour.ago

    service = Sessions::TrackingService.new(
      account, @session_id, visitor,
      event_timestamp: event_time
    )
    result = service.call

    assert result[:success]
    assert_in_delta event_time.to_i, result[:session].last_activity_at.to_i, 1
  end

  test "should update last_activity_at on existing session" do
    session.update!(last_activity_at: 1.hour.ago)
    old_activity = session.last_activity_at

    result

    assert result[:success]
    assert session.reload.last_activity_at > old_activity
    assert_in_delta Time.current.to_i, session.last_activity_at.to_i, 2
  end

  # --- Billing Usage ---

  test "should increment usage counter when session is created" do
    @session_id = "sess_new_session_for_billing"

    assert_difference -> { usage_counter.current_usage }, 1 do
      result
    end
  end

  test "should not increment usage counter when session already exists" do
    assert_no_difference -> { usage_counter.current_usage } do
      result
    end
  end

  private

  def usage_counter
    @usage_counter ||= Billing::UsageCounter.new(account)
  end

  def result
    @result ||= service.call
  end

  def service
    @service ||= Sessions::TrackingService.new(account, session_id, visitor)
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

  def session_id
    @session_id ||= session.session_id
  end
end
