# frozen_string_literal: true

require "test_helper"

module Conversions
  class TrackingServiceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    # ==========================================
    # Event-based conversion tests
    # ==========================================

    test "creates conversion from valid event_id" do
      result = build_service(event_id: event.prefix_id).call

      assert result[:success]
      assert_instance_of Conversion, result[:conversion]
      assert_equal "signup", result[:conversion].conversion_type
      assert_equal event.visitor_id, result[:conversion].visitor_id
      assert_equal event.session_id, result[:conversion].session_id
      assert_equal event.id, result[:conversion].event_id
    end

    test "returns error for invalid event_id" do
      result = build_service(event_id: "evt_nonexistent").call

      assert_not result[:success]
      assert_includes result[:errors], "Event not found"
    end

    test "returns error for event from different account" do
      other_event = events(:three)
      result = build_service(event_id: other_event.prefix_id).call

      assert_not result[:success]
      assert_includes result[:errors], "Event belongs to different account"
    end

    test "sets converted_at from event occurred_at" do
      result = build_service(event_id: event.prefix_id).call

      assert result[:success]
      assert_equal event.occurred_at, result[:conversion].converted_at
    end

    # ==========================================
    # Visitor-based conversion tests
    # ==========================================

    test "creates conversion from valid visitor_id" do
      result = build_service(visitor_id: visitor.visitor_id).call

      assert result[:success]
      assert_instance_of Conversion, result[:conversion]
      assert_equal "signup", result[:conversion].conversion_type
      assert_equal visitor.id, result[:conversion].visitor_id
    end

    test "returns error for invalid visitor_id" do
      result = build_service(visitor_id: "nonexistent_visitor_id").call

      assert_not result[:success]
      assert_includes result[:errors], "Visitor not found"
    end

    test "returns error for visitor from different account" do
      other_visitor = visitors(:three)  # From account :two
      result = build_service(visitor_id: other_visitor.visitor_id).call

      assert_not result[:success]
      assert_includes result[:errors], "Visitor not found"
    end

    test "uses most recent session for visitor-based conversion" do
      # Create a more recent session
      recent_session = account.sessions.create!(
        session_id: "recent_session_#{SecureRandom.hex(8)}",
        visitor: visitor,
        started_at: 1.hour.ago
      )

      result = build_service(visitor_id: visitor.visitor_id).call

      assert result[:success]
      assert_equal recent_session.id, result[:conversion].session_id
    end

    test "handles visitor with no sessions gracefully" do
      # Create visitor with no sessions
      new_visitor = account.visitors.create!(
        visitor_id: "no_sessions_visitor_#{SecureRandom.hex(8)}",
        first_seen_at: Time.current,
        last_seen_at: Time.current
      )

      result = build_service(visitor_id: new_visitor.visitor_id).call

      assert result[:success]
      assert_nil result[:conversion].session_id
    end

    test "sets converted_at to current time for visitor-based conversion" do
      freeze_time do
        result = build_service(visitor_id: visitor.visitor_id).call

        assert result[:success]
        assert_equal Time.current, result[:conversion].converted_at
      end
    end

    # ==========================================
    # Identifier validation tests
    # ==========================================

    test "returns error when neither event_id nor visitor_id provided" do
      result = build_service(event_id: nil, visitor_id: nil).call

      assert_not result[:success]
      assert_includes result[:errors], "event_id or visitor_id is required"
    end

    test "prefers event_id when both identifiers provided" do
      result = build_service(
        event_id: event.prefix_id,
        visitor_id: visitor.visitor_id
      ).call

      assert result[:success]
      # Should use event's data, not visitor lookup
      assert_equal event.visitor_id, result[:conversion].visitor_id
      assert_equal event.session_id, result[:conversion].session_id
      assert_equal event.id, result[:conversion].event_id
    end

    # ==========================================
    # Common tests
    # ==========================================

    test "returns error for missing conversion_type" do
      result = build_service(event_id: event.prefix_id, conversion_type: nil).call

      assert_not result[:success]
      assert_includes result[:errors], "conversion_type is required"
    end

    test "stores revenue when provided" do
      result = build_service(event_id: event.prefix_id, revenue: 99.99).call

      assert result[:success]
      assert_equal 99.99, result[:conversion].revenue.to_f
    end

    test "stores properties when provided" do
      properties = { plan: "pro", coupon: "SAVE20" }
      result = build_service(event_id: event.prefix_id, properties: properties).call

      assert result[:success]
      assert_equal "pro", result[:conversion].properties["plan"]
      assert_equal "SAVE20", result[:conversion].properties["coupon"]
    end

    test "enqueues attribution calculation job" do
      assert_enqueued_with(job: Conversions::AttributionCalculationJob) do
        result = build_service(event_id: event.prefix_id).call
        assert result[:success]
      end
    end

    test "allows nil event_id for visitor-based conversions" do
      result = build_service(visitor_id: visitor.visitor_id).call

      assert result[:success]
      assert_nil result[:conversion].event_id
    end

    private

    def build_service(
      event_id: nil,
      visitor_id: nil,
      conversion_type: "signup",
      revenue: nil,
      properties: {}
    )
      Conversions::TrackingService.new(
        account,
        {
          event_id: event_id,
          visitor_id: visitor_id,
          conversion_type: conversion_type,
          revenue: revenue,
          properties: properties
        }
      )
    end

    def account
      @account ||= accounts(:one)
    end

    def event
      @event ||= events(:one)
    end

    def visitor
      @visitor ||= visitors(:one)
    end
  end
end
