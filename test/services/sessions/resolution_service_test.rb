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

  # --- Identity-based cross-device resolution (R2) ---

  test "with identifier finds session across all visitors linked to identity" do
    # Setup: Link visitor :two (desktop) to identity
    desktop_visitor = visitors(:two)
    desktop_visitor.update!(identity: identity)

    # Create active session for desktop visitor
    desktop_session = account.sessions.create!(
      session_id: "sess_desktop_#{SecureRandom.hex(8)}",
      visitor: desktop_visitor,
      started_at: 1.hour.ago,
      last_activity_at: 5.minutes.ago,
      device_fingerprint: "fp_desktop_different"  # Different fingerprint (different device)
    )

    # Mobile visitor (not yet linked to identity) queries with identifier
    mobile_service = Sessions::ResolutionService.new(
      account: account,
      visitor_id: visitor.visitor_id,  # Mobile visitor
      ip: ip,
      user_agent: user_agent,
      identifier: { email: identity.external_id }  # Identifies as same user
    )

    result = mobile_service.call

    # Should find the desktop session via identity lookup (same user, different device)
    assert_equal desktop_session.session_id, result,
      "Should find session from another visitor linked to the same identity"
  end

  test "with identifier links current visitor to identity" do
    # Visitor is not yet linked to identity
    assert_nil visitor.identity_id

    service_with_identifier = Sessions::ResolutionService.new(
      account: account,
      visitor_id: visitor.visitor_id,
      ip: ip,
      user_agent: user_agent,
      identifier: { email: identity.external_id }
    )

    service_with_identifier.call

    # Visitor should now be linked to identity
    visitor.reload
    assert_equal identity.id, visitor.identity_id,
      "Visitor should be linked to identity after resolution with identifier"
  end

  test "without identifier does not find sessions from other visitors" do
    # Setup: Link visitor :two to identity and create active session
    desktop_visitor = visitors(:two)
    desktop_visitor.update!(identity: identity)

    desktop_session = account.sessions.create!(
      session_id: "sess_desktop_no_ident_#{SecureRandom.hex(8)}",
      visitor: desktop_visitor,
      started_at: 1.hour.ago,
      last_activity_at: 5.minutes.ago,
      device_fingerprint: "fp_desktop_different"
    )

    # Query WITHOUT identifier - should not find desktop session
    result = service.call

    assert_not_equal desktop_session.session_id, result,
      "Without identifier, should not find sessions from other visitors"
  end

  test "identifier lookup does not cross account boundaries" do
    # Create identity with same external_id in other account
    other_identity = accounts(:two).identities.create!(
      external_id: "shared_email@example.com",
      first_identified_at: Time.current,
      last_identified_at: Time.current
    )

    # Create identity in current account with same external_id
    current_identity = account.identities.create!(
      external_id: "shared_email@example.com",
      first_identified_at: Time.current,
      last_identified_at: Time.current
    )

    # Link visitor from other account to other identity
    other_visitor = visitors(:three)
    other_visitor.update!(identity: other_identity)

    other_session = accounts(:two).sessions.create!(
      session_id: "sess_other_account_#{SecureRandom.hex(8)}",
      visitor: other_visitor,
      started_at: 1.hour.ago,
      last_activity_at: 5.minutes.ago,
      device_fingerprint: device_fingerprint
    )

    # Query with identifier - should NOT find other account's session
    service_with_identifier = Sessions::ResolutionService.new(
      account: account,
      visitor_id: visitor.visitor_id,
      ip: ip,
      user_agent: user_agent,
      identifier: { email: "shared_email@example.com" }
    )

    result = service_with_identifier.call

    assert_not_equal other_session.session_id, result,
      "Should not find sessions from other accounts even with same identifier"
  end

  test "identity session must be within 30 minute timeout" do
    # Setup: Link visitor :two to identity
    desktop_visitor = visitors(:two)
    desktop_visitor.update!(identity: identity)

    # Create session that's expired (more than 30 min ago)
    expired_session = account.sessions.create!(
      session_id: "sess_expired_#{SecureRandom.hex(8)}",
      visitor: desktop_visitor,
      started_at: 2.hours.ago,
      last_activity_at: 45.minutes.ago,  # Expired
      device_fingerprint: "fp_desktop"
    )

    service_with_identifier = Sessions::ResolutionService.new(
      account: account,
      visitor_id: visitor.visitor_id,
      ip: ip,
      user_agent: user_agent,
      identifier: { email: identity.external_id }
    )

    result = service_with_identifier.call

    assert_not_equal expired_session.session_id, result,
      "Should not find expired sessions even via identity lookup"
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

  def identity
    @identity ||= identities(:one)
  end
end
