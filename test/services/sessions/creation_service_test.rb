# frozen_string_literal: true

require "test_helper"

class Sessions::CreationServiceTest < ActiveSupport::TestCase
  # --- Concurrent Turbo Frame Deduplication ---

  test "concurrent requests with same session_id should reuse canonical visitor" do
    # First request creates visitor + session
    first_params = {
      visitor_id: "vis_turbo_frame_1",
      session_id: "sess_shared_turbo_session",
      url: "https://example.com/page"
    }
    first_result = Sessions::CreationService.new(account, first_params).call

    assert first_result[:success]
    first_visitor = account.visitors.find_by(visitor_id: "vis_turbo_frame_1")
    assert first_visitor

    # Second request with SAME session_id but DIFFERENT visitor_id
    second_params = {
      visitor_id: "vis_turbo_frame_2",
      session_id: "sess_shared_turbo_session",
      url: "https://example.com/page"
    }
    second_result = Sessions::CreationService.new(account, second_params).call

    assert second_result[:success]

    # Should NOT create a new visitor - should reuse first visitor
    assert_nil account.visitors.find_by(visitor_id: "vis_turbo_frame_2"),
      "Second request should reuse canonical visitor, not create new one"

    # Both sessions should belong to first visitor
    sessions = account.sessions.where(session_id: "sess_shared_turbo_session")
    assert_equal 1, sessions.count, "Should only have one session"
    assert_equal first_visitor, sessions.first.visitor
  end

  test "requests with different session_ids should create different visitors" do
    first_params = {
      visitor_id: "vis_different_1",
      session_id: "sess_different_1",
      url: "https://example.com/page"
    }
    Sessions::CreationService.new(account, first_params).call

    second_params = {
      visitor_id: "vis_different_2",
      session_id: "sess_different_2",
      url: "https://example.com/page"
    }
    Sessions::CreationService.new(account, second_params).call

    # Both visitors should exist (different session_ids = different users)
    assert account.visitors.exists?(visitor_id: "vis_different_1")
    assert account.visitors.exists?(visitor_id: "vis_different_2")
  end

  test "same session_id after 30 seconds should reuse existing sessions visitor" do
    # Create first session
    first_params = {
      visitor_id: "vis_old_session",
      session_id: "sess_time_bounded",
      url: "https://example.com/page"
    }
    Sessions::CreationService.new(account, first_params).call

    # Simulate time passing - update the session to appear old
    account.sessions.where(session_id: "sess_time_bounded").update_all(
      created_at: 31.seconds.ago
    )

    # New request with same session_id but different visitor_id
    # Should use the existing session's visitor (session_id is unique)
    second_params = {
      visitor_id: "vis_new_session",
      session_id: "sess_time_bounded",
      url: "https://example.com/page"
    }
    result = Sessions::CreationService.new(account, second_params).call

    assert result[:success]
    # Original visitor should exist
    assert account.visitors.exists?(visitor_id: "vis_old_session")
    # New visitor should NOT be created - session_id is unique, so we use existing session's visitor
    refute account.visitors.exists?(visitor_id: "vis_new_session"),
      "Should NOT create new visitor - session_id already exists, use existing session's visitor"
    # Should still have only one session
    assert_equal 1, account.sessions.where(session_id: "sess_time_bounded").count
  end

  # --- Fingerprint-Based Advisory Lock (Phase 6) ---

  test "concurrent requests with different session_ids but same fingerprint should reuse visitor" do
    fingerprint = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]

    first_params = {
      visitor_id: "vis_fp_concurrent_1",
      session_id: "sess_random_uuid_1",
      device_fingerprint: fingerprint,
      url: "https://example.com/page"
    }
    first_result = Sessions::CreationService.new(account, first_params).call

    assert first_result[:success]
    first_visitor = account.visitors.find_by(visitor_id: "vis_fp_concurrent_1")
    assert first_visitor

    second_params = {
      visitor_id: "vis_fp_concurrent_2",
      session_id: "sess_random_uuid_2",
      device_fingerprint: fingerprint,
      url: "https://example.com/page"
    }
    second_result = Sessions::CreationService.new(account, second_params).call

    assert second_result[:success]

    refute account.visitors.exists?(visitor_id: "vis_fp_concurrent_2"),
      "Second request with same fingerprint should reuse first visitor, not create new one"

    # With session continuity, second request reuses the first session entirely
    assert_nil account.sessions.find_by(session_id: "sess_random_uuid_2"),
      "Second request should reuse existing session, not create sess_random_uuid_2"
    assert_equal 1, account.sessions.where(device_fingerprint: fingerprint).count,
      "Same fingerprint should result in one session"
  end

  test "requests with same fingerprint but different session_ids create only one visitor" do
    fingerprint = Digest::SHA256.hexdigest("192.168.1.1|Safari/17")[0, 32]

    3.times do |i|
      params = {
        visitor_id: "vis_burst_#{i}",
        session_id: "sess_burst_#{i}",
        device_fingerprint: fingerprint,
        url: "https://example.com/page"
      }
      result = Sessions::CreationService.new(account, params).call
      assert result[:success]
    end

    created_visitors = account.visitors.where("visitor_id LIKE ?", "vis_burst_%")
    assert_equal 1, created_visitors.count,
      "All requests with same fingerprint should resolve to single visitor"
  end

  test "requests without fingerprint fall back to session_id lock behavior" do
    first_params = {
      visitor_id: "vis_no_fp_1",
      session_id: "sess_no_fp_1",
      url: "https://example.com/page"
    }
    Sessions::CreationService.new(account, first_params).call

    second_params = {
      visitor_id: "vis_no_fp_2",
      session_id: "sess_no_fp_2",
      url: "https://example.com/other"
    }
    Sessions::CreationService.new(account, second_params).call

    assert account.visitors.exists?(visitor_id: "vis_no_fp_1")
    assert account.visitors.exists?(visitor_id: "vis_no_fp_2"),
      "Without fingerprint, different session_ids should create different visitors"
  end

  test "different fingerprints create different visitors even with same timing" do
    fp_a = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]
    fp_b = Digest::SHA256.hexdigest("10.0.0.2|Firefox/130")[0, 32]

    params_a = {
      visitor_id: "vis_device_a",
      session_id: "sess_device_a",
      device_fingerprint: fp_a,
      url: "https://example.com/page"
    }
    Sessions::CreationService.new(account, params_a).call

    params_b = {
      visitor_id: "vis_device_b",
      session_id: "sess_device_b",
      device_fingerprint: fp_b,
      url: "https://example.com/page"
    }
    Sessions::CreationService.new(account, params_b).call

    assert account.visitors.exists?(visitor_id: "vis_device_a")
    assert account.visitors.exists?(visitor_id: "vis_device_b"),
      "Different fingerprints (different devices) should create separate visitors"
  end

  # --- Session Continuity (reuse active sessions) ---

  test "internal navigation reuses existing active session instead of creating new" do
    fingerprint = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]

    # Landing from Google — creates Session A
    landing = {
      visitor_id: visitor.visitor_id,
      session_id: "sess_landing_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/?utm_source=google&utm_medium=cpc",
      referrer: "https://www.google.com/"
    }
    Sessions::CreationService.new(account, landing).call

    session_a = account.sessions.find_by(session_id: "sess_landing_uuid")
    assert session_a
    assert_equal "paid_search", session_a.channel

    # Age the session past 30-second dedup window but within 30-minute session window
    session_a.update_columns(last_activity_at: 2.minutes.ago, created_at: 2.minutes.ago)

    # Internal navigation — same visitor, same fingerprint, self-referral
    internal_nav = {
      visitor_id: visitor.visitor_id,
      session_id: "sess_internal_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/search",
      referrer: "https://example.com/"
    }
    result = Sessions::CreationService.new(account, internal_nav).call

    assert result[:success]
    # Should NOT create a new session
    assert_nil account.sessions.find_by(session_id: "sess_internal_uuid"),
      "Internal navigation should reuse existing session, not create new one"
    # Should still have only the landing session
    assert_equal "paid_search", result[:channel],
      "Should return the reused session's channel (paid_search), not self-referral"
  end

  test "new UTM params create new session even with active session" do
    fingerprint = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]

    # First visit — direct
    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_direct_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/"
    }).call

    session_a = account.sessions.find_by(session_id: "sess_direct_uuid")
    session_a.update_columns(last_activity_at: 5.minutes.ago, created_at: 5.minutes.ago)

    # New visit from Google Ad — has UTM
    result = Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_google_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/?utm_source=google&utm_medium=cpc",
      referrer: "https://www.google.com/"
    }).call

    assert result[:success]
    # SHOULD create a new session (new traffic source)
    assert account.sessions.find_by(session_id: "sess_google_uuid"),
      "New UTM params should create a new session, not reuse existing"
    assert_equal "paid_search", result[:channel]
  end

  test "new click_id creates new session even with active session" do
    fingerprint = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_existing_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/"
    }).call

    account.sessions.find_by(session_id: "sess_existing_uuid")
      .update_columns(last_activity_at: 5.minutes.ago, created_at: 5.minutes.ago)

    result = Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_gclid_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/?gclid=abc123"
    }).call

    assert result[:success]
    assert account.sessions.find_by(session_id: "sess_gclid_uuid"),
      "Click ID should create a new session (new traffic source)"
  end

  test "external referrer creates new session even with active session" do
    fingerprint = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_first_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/"
    }).call

    account.sessions.find_by(session_id: "sess_first_uuid")
      .update_columns(last_activity_at: 5.minutes.ago, created_at: 5.minutes.ago)

    result = Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_ext_ref_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/landing",
      referrer: "https://facebook.com/post/123"
    }).call

    assert result[:success]
    assert account.sessions.find_by(session_id: "sess_ext_ref_uuid"),
      "External referrer should create a new session"
  end

  test "no referrer reuses existing active session" do
    fingerprint = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_orig_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/",
      referrer: "https://www.google.com/"
    }).call

    session_a = account.sessions.find_by(session_id: "sess_orig_uuid")
    session_a.update_columns(last_activity_at: 5.minutes.ago, created_at: 5.minutes.ago)

    # Next request has no referrer (e.g., direct navigation within the site)
    result = Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_no_ref_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/page"
    }).call

    assert result[:success]
    assert_nil account.sessions.find_by(session_id: "sess_no_ref_uuid"),
      "No referrer should reuse existing session (continuation)"
  end

  test "expired session creates new session even for internal navigation" do
    fingerprint = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_old_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/"
    }).call

    # Age past 30-minute session window
    account.sessions.find_by(session_id: "sess_old_uuid")
      .update_columns(last_activity_at: 31.minutes.ago, created_at: 31.minutes.ago)

    result = Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_after_timeout_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/page",
      referrer: "https://example.com/"
    }).call

    assert result[:success]
    assert account.sessions.find_by(session_id: "sess_after_timeout_uuid"),
      "Expired session (>30 min) should create new even for internal nav"
  end

  test "reused session preserves original attribution" do
    fingerprint = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_preserve_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/?utm_source=google&utm_medium=cpc",
      referrer: "https://www.google.com/"
    }).call

    session_a = account.sessions.find_by(session_id: "sess_preserve_uuid")
    session_a.update_columns(last_activity_at: 2.minutes.ago, created_at: 2.minutes.ago)

    original_utm = session_a.initial_utm
    original_referrer = session_a.initial_referrer
    original_channel = session_a.channel

    # Internal navigation with self-referral
    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_reuse_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/search",
      referrer: "https://example.com/"
    }).call

    session_a.reload
    assert_equal original_utm, session_a.initial_utm,
      "Reused session should preserve original UTM"
    assert_equal original_referrer, session_a.initial_referrer,
      "Reused session should preserve original referrer"
    assert_equal original_channel, session_a.channel,
      "Reused session should preserve original channel"
  end

  test "reused session updates last_activity_at" do
    fingerprint = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_activity_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/"
    }).call

    session_a = account.sessions.find_by(session_id: "sess_activity_uuid")
    session_a.update_columns(last_activity_at: 10.minutes.ago, created_at: 10.minutes.ago)
    old_activity = session_a.last_activity_at

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_activity2_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/page",
      referrer: "https://example.com/"
    }).call

    session_a.reload
    assert session_a.last_activity_at > old_activity,
      "Reused session should update last_activity_at"
  end

  test "reused session does not increment billing usage" do
    fingerprint = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_billing_uuid",
      device_fingerprint: fingerprint,
      url: "https://example.com/"
    }).call

    account.sessions.find_by(session_id: "sess_billing_uuid")
      .update_columns(last_activity_at: 2.minutes.ago, created_at: 2.minutes.ago)

    assert_no_difference -> { usage_counter.current_usage } do
      Sessions::CreationService.new(account, {
        visitor_id: visitor.visitor_id,
        session_id: "sess_billing2_uuid",
        device_fingerprint: fingerprint,
        url: "https://example.com/page",
        referrer: "https://example.com/"
      }).call
    end
  end

  test "no fingerprint falls back to visitor_id matching and reuses session" do
    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_nofp_1",
      url: "https://example.com/?utm_source=google&utm_medium=cpc",
      referrer: "https://www.google.com/"
    }).call

    session_a = account.sessions.find_by(session_id: "sess_nofp_1")
    session_a.update_columns(last_activity_at: 2.minutes.ago, created_at: 2.minutes.ago)

    result = Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_nofp_2",
      url: "https://example.com/page",
      referrer: "https://example.com/"
    }).call

    assert result[:success]
    assert_nil account.sessions.find_by(session_id: "sess_nofp_2"),
      "Without fingerprint, visitor_id fallback should reuse existing session"
    assert_equal "paid_search", result[:channel],
      "Should return the reused session's channel"
  end

  # --- Fingerprint Fallback (visitor_id-only matching) ---

  test "different fingerprint with same visitor_id reuses session via fallback" do
    fp_landing = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]
    fp_changed = Digest::SHA256.hexdigest("10.0.0.99|Chrome/120")[0, 32]

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_fp_land",
      device_fingerprint: fp_landing,
      url: "https://example.com/?utm_source=google&utm_medium=organic",
      referrer: "https://www.google.com/"
    }).call

    session_a = account.sessions.find_by(session_id: "sess_fp_land")
    session_a.update_columns(last_activity_at: 2.minutes.ago, created_at: 2.minutes.ago)

    result = Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_fp_nav",
      device_fingerprint: fp_changed,
      url: "https://example.com/search",
      referrer: "https://example.com/"
    }).call

    assert result[:success]
    assert_nil account.sessions.find_by(session_id: "sess_fp_nav"),
      "Different fingerprint should fall back to visitor_id and reuse session"
    assert_equal "organic_search", result[:channel],
      "Should return the reused session's channel, not self-referral"
  end

  test "different fingerprint fallback preserves original attribution" do
    fp_a = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]
    fp_b = Digest::SHA256.hexdigest("10.0.0.50|Chrome/120")[0, 32]

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_fp_preserve",
      device_fingerprint: fp_a,
      url: "https://example.com/?utm_source=google&utm_medium=cpc",
      referrer: "https://www.google.com/"
    }).call

    session_a = account.sessions.find_by(session_id: "sess_fp_preserve")
    session_a.update_columns(last_activity_at: 2.minutes.ago, created_at: 2.minutes.ago)

    original_utm = session_a.initial_utm
    original_channel = session_a.channel

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_fp_preserve_nav",
      device_fingerprint: fp_b,
      url: "https://example.com/search",
      referrer: "https://example.com/"
    }).call

    session_a.reload
    assert_equal original_utm, session_a.initial_utm,
      "Fallback-reused session should preserve original UTM"
    assert_equal original_channel, session_a.channel,
      "Fallback-reused session should preserve original channel"
  end

  test "different fingerprint with new UTM creates new session" do
    fp_a = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]
    fp_b = Digest::SHA256.hexdigest("10.0.0.50|Chrome/120")[0, 32]

    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_fp_first",
      device_fingerprint: fp_a,
      url: "https://example.com/"
    }).call

    account.sessions.find_by(session_id: "sess_fp_first")
      .update_columns(last_activity_at: 5.minutes.ago, created_at: 5.minutes.ago)

    result = Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_fp_new_utm",
      device_fingerprint: fp_b,
      url: "https://example.com/?utm_source=facebook&utm_medium=paid_social",
      referrer: "https://facebook.com/ad/123"
    }).call

    assert result[:success]
    assert account.sessions.find_by(session_id: "sess_fp_new_utm"),
      "New traffic source should create new session even with visitor_id fallback"
  end

  test "visitor_id fallback does not match sessions from different visitors" do
    fp_a = Digest::SHA256.hexdigest("10.0.0.1|Chrome/120")[0, 32]
    fp_b = Digest::SHA256.hexdigest("10.0.0.99|Chrome/120")[0, 32]

    # Visitor A creates a session
    Sessions::CreationService.new(account, {
      visitor_id: visitor.visitor_id,
      session_id: "sess_visitor_a",
      device_fingerprint: fp_a,
      url: "https://example.com/?utm_source=google&utm_medium=cpc"
    }).call

    account.sessions.find_by(session_id: "sess_visitor_a")
      .update_columns(last_activity_at: 2.minutes.ago, created_at: 2.minutes.ago)

    # Visitor B (different visitor_id) should NOT reuse Visitor A's session
    result = Sessions::CreationService.new(account, {
      visitor_id: "vis_totally_different",
      session_id: "sess_visitor_b",
      device_fingerprint: fp_b,
      url: "https://example.com/page",
      referrer: "https://example.com/"
    }).call

    assert result[:success]
    assert account.sessions.find_by(session_id: "sess_visitor_b"),
      "Different visitor_id should create new session, not reuse another visitor's"
  end

  # --- Billing Usage ---

  test "should increment usage counter when new session is created with existing visitor" do
    @params = {
      visitor_id: visitor.visitor_id,
      session_id: "sess_new_session_existing_visitor",
      url: "https://example.com/page"
    }

    assert_difference -> { usage_counter.current_usage }, 1 do
      result
    end
  end

  test "should increment usage counter for both visitor and session when both are new" do
    @params = {
      visitor_id: "vis_brand_new_visitor",
      session_id: "sess_brand_new_session",
      url: "https://example.com/page"
    }

    assert_difference -> { usage_counter.current_usage }, 2 do
      result
    end
  end

  test "should not increment usage counter when session already exists" do
    # Create the session first
    service.call

    # Second call with same session should not increment
    assert_no_difference -> { usage_counter.current_usage } do
      Sessions::CreationService.new(account, params).call
    end
  end

  private

  def result
    @result ||= service.call
  end

  def service
    @service ||= Sessions::CreationService.new(account, params)
  end

  def params
    @params ||= {
      visitor_id: "vis_new_visitor_123",
      session_id: "sess_new_session_123",
      url: "https://example.com/page"
    }
  end

  def account
    @account ||= accounts(:one)
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def usage_counter
    @usage_counter ||= Billing::UsageCounter.new(account)
  end
end
