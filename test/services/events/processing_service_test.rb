# frozen_string_literal: true

require "test_helper"

class Events::ProcessingServiceTest < ActiveSupport::TestCase
  test "should create event with valid data" do
    assert_difference -> { Event.count }, 1 do
      assert result[:success]
      assert_predicate result[:event], :persisted?
      assert_equal "page_view", result[:event].event_type
    end
  end

  test "should associate event with account" do
    assert_equal account, result[:event].account
  end

  test "should return error for unknown visitor_id" do
    @visitor_id = "vis_unknown_visitor"
    @session_id = "sess_any_session"

    assert_no_difference -> { Visitor.count } do
      assert_not result[:success]
      assert_includes result[:errors], "Visitor not found"
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
    existing_session.update_columns(channel: "paid_search")
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
    assert_predicate result[:errors], :present?
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

  # Funnel tests
  test "should save funnel to event" do
    @event_data = valid_event_data.merge("funnel" => "signup")

    assert result[:success]
    assert_equal "signup", result[:event].funnel
  end

  test "should allow nil funnel" do
    @event_data = valid_event_data.merge("funnel" => nil)

    assert result[:success]
    assert_nil result[:event].funnel
  end

  test "should save funnel with symbol key" do
    @event_data = valid_event_data.merge(funnel: "purchase")

    assert result[:success]
    assert_equal "purchase", result[:event].funnel
  end

  # --- Channel attribution preservation ---

  test "should not overwrite session channel when initial_utm is empty hash" do
    # THE BUG: session attributed by referrer has channel but empty UTM.
    # {}.blank? == true in Rails, so the guard fails and channel is overwritten to "direct"
    session.update_columns(channel: "organic_search", initial_utm: {}, initial_referrer: "https://www.google.com/")

    @event_data = {
      "event_type" => "add_to_cart",
      "visitor_id" => visitor_id,
      "session_id" => session_id,
      "timestamp" => Time.current.iso8601,
      "properties" => { "product" => "Widget" }
    }.freeze

    assert result[:success]
    session.reload

    assert_equal "organic_search", session.channel
    assert_equal "https://www.google.com/", session.initial_referrer
  end

  test "should not overwrite session channel attributed by click IDs" do
    session.update_columns(channel: "paid_search", initial_utm: {}, click_ids: { gclid: "abc123" }.to_json)

    @event_data = {
      "event_type" => "add_to_cart",
      "visitor_id" => visitor_id,
      "session_id" => session_id,
      "timestamp" => Time.current.iso8601,
      "properties" => { "product" => "Widget" }
    }.freeze

    assert result[:success]
    session.reload

    assert_equal "paid_search", session.channel
  end

  test "should set channel with full context when session has no channel" do
    # TrackingService path: session created without channel
    @session_id = "sess_no_channel"
    @event_data = {
      "event_type" => "page_view",
      "visitor_id" => visitor_id,
      "session_id" => "sess_no_channel",
      "timestamp" => Time.current.iso8601,
      "properties" => { "page" => "/landing" },
      "url" => "https://example.com/landing?gclid=xyz789"
    }.freeze

    assert result[:success]
    new_session = result[:event].session

    assert_equal "paid_search", new_session.channel
  end

  test "should set channel from referrer when session has no channel" do
    @session_id = "sess_referrer_only"
    @event_data = {
      "event_type" => "page_view",
      "visitor_id" => visitor_id,
      "session_id" => "sess_referrer_only",
      "timestamp" => Time.current.iso8601,
      "properties" => { "page" => "/landing" },
      "url" => "https://example.com/landing",
      "referrer" => "https://www.google.com/search?q=test"
    }.freeze

    assert result[:success]
    new_session = result[:event].session

    assert_equal "organic_search", new_session.channel
  end

  test "should set channel as direct when session has no channel and no signals" do
    @session_id = "sess_genuinely_direct"
    @event_data = {
      "event_type" => "page_view",
      "visitor_id" => visitor_id,
      "session_id" => "sess_genuinely_direct",
      "timestamp" => Time.current.iso8601,
      "properties" => { "page" => "/home" }
    }.freeze

    assert result[:success]
    new_session = result[:event].session

    assert_equal "direct", new_session.channel
  end

  test "second event should not change channel set by first event" do
    @session_id = "sess_multi_event"
    first_event_data = {
      "event_type" => "page_view",
      "visitor_id" => visitor_id,
      "session_id" => "sess_multi_event",
      "timestamp" => Time.current.iso8601,
      "properties" => { "page" => "/landing" },
      "referrer" => "https://www.google.com/"
    }.freeze

    first_result = Events::ProcessingService.new(account, first_event_data).call

    assert first_result[:success]
    new_session = first_result[:event].session

    assert_equal "organic_search", new_session.channel

    # Second event with no referrer — should not overwrite
    second_event_data = {
      "event_type" => "add_to_cart",
      "visitor_id" => visitor_id,
      "session_id" => "sess_multi_event",
      "timestamp" => Time.current.iso8601,
      "properties" => { "product" => "Widget" }
    }.freeze

    second_result = Events::ProcessingService.new(account, second_event_data).call

    assert second_result[:success]
    new_session.reload

    assert_equal "organic_search", new_session.channel
  end

  # --- Server-side session resolution ---

  test "should resolve session server-side when ip and user_agent provided" do
    # Existing session with matching fingerprint
    session.update!(
      device_fingerprint: device_fingerprint,
      last_activity_at: 10.minutes.ago
    )

    @event_data = valid_event_data.merge(
      "ip" => test_ip,
      "user_agent" => test_user_agent,
      "session_id" => "sess_should_be_ignored"  # Client-sent, should be ignored
    )

    assert result[:success]
    # Should use existing session, not the client-sent session_id
    assert_equal session.session_id, result[:event].session.session_id
  end

  test "should generate new session_id when no active session exists" do
    @session_id = nil
    @event_data = valid_event_data.merge(
      "ip" => test_ip,
      "user_agent" => test_user_agent,
      "session_id" => nil
    )

    assert_difference -> { Session.count }, 1 do
      assert result[:success]
      # Should have generated a deterministic session_id
      assert_predicate result[:event].session.session_id, :present?
      assert_equal 32, result[:event].session.session_id.length
    end
  end

  test "should store device_fingerprint on new session" do
    @event_data = valid_event_data.merge(
      "ip" => test_ip,
      "user_agent" => test_user_agent,
      "session_id" => "sess_new_with_fingerprint"
    )

    assert result[:success]
    assert_equal device_fingerprint, result[:event].session.device_fingerprint
  end

  test "should fallback to client session_id when ip/user_agent missing" do
    # No ip/user_agent = can't do server-side resolution, use client session_id
    @event_data = valid_event_data  # No ip or user_agent

    assert result[:success]
    assert_equal session_id, result[:event].session.session_id
  end

  # --- Fingerprint fallback (mismatched IP) ---

  test "event with mismatched fingerprint joins existing active session" do
    # Session created by SDK middleware with one IP
    original_ip = "10.0.0.1"
    original_fingerprint = Digest::SHA256.hexdigest("#{original_ip}|#{test_user_agent}")[0, 32]

    session.update!(
      device_fingerprint: original_fingerprint,
      last_activity_at: 5.minutes.ago
    )

    # Event arrives with different IP (mobile network rotation, CDN edge, etc.)
    different_ip = "10.0.0.99"
    @event_data = {
      "event_type" => "add_to_cart",
      "visitor_id" => visitor_id,
      "ip" => different_ip,
      "user_agent" => test_user_agent,
      "timestamp" => Time.current.iso8601,
      "properties" => { "product" => "Widget" }
    }.freeze

    assert_no_difference -> { Session.count } do
      assert result[:success]
      assert_equal session.session_id, result[:event].session.session_id
    end
  end

  # --- Visitor fingerprint deduplication ---

  test "should pass device_fingerprint to LookupService for visitor deduplication" do
    # First request creates a visitor and session with fingerprint
    first_visitor = account.visitors.create!(visitor_id: "vis_first_request")
    first_session = account.sessions.create!(
      visitor: first_visitor,
      session_id: "sess_first",
      device_fingerprint: device_fingerprint,
      started_at: Time.current
    )

    # Second concurrent request with DIFFERENT visitor_id but SAME fingerprint
    @visitor_id = nil  # Clear memoization
    @event_data = {
      "event_type" => "page_view",
      "visitor_id" => "vis_second_request",  # Different visitor_id
      "ip" => test_ip,
      "user_agent" => test_user_agent,
      "timestamp" => Time.current.iso8601,
      "properties" => { "url" => "https://example.com" }
    }.freeze

    assert_no_difference -> { Visitor.count } do
      assert result[:success]
      # Should use the first visitor (deduplicated via fingerprint)
      assert_equal first_visitor, result[:event].visitor
    end
  end

  def test_ip
    "192.168.1.100"
  end

  def test_user_agent
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
  end

  def device_fingerprint
    @device_fingerprint ||= Digest::SHA256.hexdigest("#{test_ip}|#{test_user_agent}")[0, 32]
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
