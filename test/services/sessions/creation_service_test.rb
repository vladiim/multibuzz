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

    assert_equal first_visitor, account.sessions.find_by(session_id: "sess_random_uuid_2").visitor,
      "Second session should belong to the first visitor (canonical via fingerprint)"
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
