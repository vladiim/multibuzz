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

  test "same session_id after 30 seconds should create new visitor" do
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

    # New request with same session_id should create new visitor
    second_params = {
      visitor_id: "vis_new_session",
      session_id: "sess_time_bounded",
      url: "https://example.com/page"
    }
    Sessions::CreationService.new(account, second_params).call

    # New visitor should be created (old session is outside 30-second window)
    assert account.visitors.exists?(visitor_id: "vis_old_session")
    assert account.visitors.exists?(visitor_id: "vis_new_session")
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
