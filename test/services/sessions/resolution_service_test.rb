require "test_helper"

class Sessions::ResolutionServiceTest < ActiveSupport::TestCase
  # --- Continue existing session (within 30 min, same device) ---

  test "returns existing session_id when last_activity_at is within 30 minutes" do
    session.update!(
      last_activity_at: 10.minutes.ago,
      device_fingerprint: device_fingerprint
    )

    result = service.call

    assert_equal session.session_id, result
  end

  test "returns existing session_id when last_activity_at is exactly 30 minutes ago" do
    session.update!(
      last_activity_at: 30.minutes.ago + 1.second,
      device_fingerprint: device_fingerprint
    )

    result = service.call

    assert_equal session.session_id, result
  end

  # --- New session (timeout expired) ---

  test "generates new ID when last_activity_at is older than 30 minutes" do
    session.update!(
      last_activity_at: 31.minutes.ago,
      device_fingerprint: device_fingerprint
    )

    result = service.call

    assert_not_equal session.session_id, result
    assert_equal 32, result.length  # SHA256 truncated to 32 chars
  end

  test "generates new ID when session has ended" do
    session.update!(
      last_activity_at: 10.minutes.ago,
      device_fingerprint: device_fingerprint,
      ended_at: 5.minutes.ago
    )

    result = service.call

    assert_not_equal session.session_id, result
  end

  # --- New visitor ---

  test "generates new ID for unknown visitor_id" do
    result = Sessions::ResolutionService.new(
      account: account,
      visitor_id: "vis_unknown_visitor",
      ip: ip,
      user_agent: user_agent
    ).call

    assert_equal 32, result.length
  end

  # --- Deterministic ID generation ---

  test "generates same deterministic ID for same inputs within 5 minute window" do
    # Two separate calls with same inputs should get same session_id
    result1 = service_for_unknown_visitor.call
    result2 = service_for_unknown_visitor.call

    assert_equal result1, result2
  end

  test "generates different ID after 5 minute window passes" do
    result1 = nil

    travel_to(Time.current) do
      result1 = service_for_unknown_visitor.call
    end

    travel_to(6.minutes.from_now) do
      result2 = service_for_unknown_visitor.call
      assert_not_equal result1, result2
    end
  end

  # --- Device fingerprint (same visitor, different device) ---

  test "same visitor on different device gets different session" do
    session.update!(
      last_activity_at: 10.minutes.ago,
      device_fingerprint: device_fingerprint
    )

    # Same visitor but different user agent (different device)
    different_device_service = Sessions::ResolutionService.new(
      account: account,
      visitor_id: visitor.visitor_id,
      ip: ip,
      user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)"
    )

    result = different_device_service.call

    # Should NOT return the existing session - it's a different device
    assert_not_equal session.session_id, result
  end

  test "same visitor on same device within timeout continues session" do
    session.update!(
      last_activity_at: 10.minutes.ago,
      device_fingerprint: device_fingerprint
    )

    result = service.call

    assert_equal session.session_id, result
  end

  # --- Account isolation ---

  test "does not return session from different account" do
    other_session = sessions(:other_account_session)
    other_session.update!(
      last_activity_at: 10.minutes.ago,
      device_fingerprint: device_fingerprint
    )

    # Using account :one but looking for session that belongs to account :two
    result = Sessions::ResolutionService.new(
      account: account,
      visitor_id: other_session.visitor.visitor_id,
      ip: ip,
      user_agent: user_agent
    ).call

    assert_not_equal other_session.session_id, result
  end

  # --- Edge cases ---

  test "handles nil last_activity_at gracefully (legacy sessions)" do
    session.update!(
      last_activity_at: nil,
      device_fingerprint: device_fingerprint
    )

    result = service.call

    # Should generate new session since no activity timestamp
    assert_not_equal session.session_id, result
    assert_equal 32, result.length
  end

  test "handles nil device_fingerprint gracefully (legacy sessions)" do
    session.update!(
      last_activity_at: 10.minutes.ago,
      device_fingerprint: nil
    )

    result = service.call

    # Should generate new session since fingerprint doesn't match
    assert_not_equal session.session_id, result
    assert_equal 32, result.length
  end

  private

  def service
    @service ||= Sessions::ResolutionService.new(
      account: account,
      visitor_id: visitor.visitor_id,
      ip: ip,
      user_agent: user_agent
    )
  end

  def service_for_unknown_visitor
    Sessions::ResolutionService.new(
      account: account,
      visitor_id: "vis_brand_new_visitor",
      ip: ip,
      user_agent: user_agent
    )
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

  def ip
    "192.168.1.100"
  end

  def user_agent
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
  end

  def device_fingerprint
    @device_fingerprint ||= Digest::SHA256.hexdigest("#{ip}|#{user_agent}")[0, 32]
  end
end
