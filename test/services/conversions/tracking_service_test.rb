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

    test "flattens nested properties from ActionController::Parameters" do
      # Simulates what happens when SDK sends { properties: { properties: { location: "Sydney" } } }
      params = ActionController::Parameters.new({
        url: "https://example.com",
        referrer: "https://google.com",
        properties: { location: "Sydney", plan: "pro" }
      })
      permitted = params.permit(:url, :referrer, properties: {})
      nested_properties = permitted

      result = build_service(event_id: event.prefix_id, properties: nested_properties).call

      assert result[:success]
      assert_equal "Sydney", result[:conversion].properties["location"]
      assert_equal "pro", result[:conversion].properties["plan"]
      assert_nil result[:conversion].properties["properties"], "nested 'properties' key should be flattened"
    end

    test "attribution job enqueued via model callback" do
      # Job is enqueued by Conversion::Callbacks, not the service
      result = build_service(event_id: event.prefix_id).call
      assert result[:success]
      assert_enqueued_jobs 1, only: Conversions::AttributionCalculationJob
    end

    test "allows nil event_id for visitor-based conversions" do
      result = build_service(visitor_id: visitor.visitor_id).call

      assert result[:success]
      assert_nil result[:conversion].event_id
    end

    # ==========================================
    # Revenue normalization tests
    # ==========================================

    test "normalizes zero revenue to nil" do
      result = build_service(event_id: event.prefix_id, revenue: 0).call

      assert result[:success]
      assert_nil result[:conversion].revenue
    end

    test "normalizes string zero revenue to nil" do
      result = build_service(event_id: event.prefix_id, revenue: "0").call

      assert result[:success]
      assert_nil result[:conversion].revenue
    end

    test "handles invalid revenue gracefully" do
      # Object that raises TypeError on to_f
      invalid_revenue = Object.new

      result = build_service(event_id: event.prefix_id, revenue: invalid_revenue).call

      assert result[:success]
      assert_nil result[:conversion].revenue
    end

    test "preserves valid numeric revenue" do
      result = build_service(event_id: event.prefix_id, revenue: 150.50).call

      assert result[:success]
      assert_equal 150.50, result[:conversion].revenue.to_f
    end

    test "preserves valid string revenue" do
      result = build_service(event_id: event.prefix_id, revenue: "99.99").call

      assert result[:success]
      assert_equal 99.99, result[:conversion].revenue.to_f
    end

    # ==========================================
    # Currency tests
    # ==========================================

    test "stores currency when provided" do
      result = build_service(event_id: event.prefix_id, currency: "EUR").call

      assert result[:success]
      assert_equal "EUR", result[:conversion].currency
    end

    test "uses default USD when currency not provided" do
      result = build_service(event_id: event.prefix_id).call

      assert result[:success]
      assert_equal "USD", result[:conversion].currency
    end

    # ==========================================
    # Acquisition attribution tests
    # ==========================================

    test "links conversion to identity when user_id provided" do
      result = build_service(
        event_id: event.prefix_id,
        user_id: identity.external_id
      ).call

      assert result[:success]
      assert_equal identity.id, result[:conversion].identity_id
    end

    test "conversion has nil identity_id when user_id not provided" do
      result = build_service(event_id: event.prefix_id).call

      assert result[:success]
      assert_nil result[:conversion].identity_id
    end

    test "conversion has nil identity_id when user_id does not exist" do
      result = build_service(
        event_id: event.prefix_id,
        user_id: "nonexistent_user_id"
      ).call

      assert result[:success]
      assert_nil result[:conversion].identity_id
    end

    test "conversion has nil identity_id when user_id belongs to different account" do
      other_identity = identities(:other_account_identity)
      result = build_service(
        event_id: event.prefix_id,
        user_id: other_identity.external_id
      ).call

      assert result[:success]
      assert_nil result[:conversion].identity_id
    end

    test "sets is_acquisition flag when provided" do
      result = build_service(
        event_id: event.prefix_id,
        user_id: identity.external_id,
        is_acquisition: true
      ).call

      assert result[:success]
      assert_equal true, result[:conversion].is_acquisition
    end

    test "is_acquisition defaults to false" do
      result = build_service(
        event_id: event.prefix_id,
        user_id: identity.external_id
      ).call

      assert result[:success]
      assert_equal false, result[:conversion].is_acquisition
    end

    test "sets inherit_acquisition transient attribute when provided" do
      result = build_service(
        event_id: event.prefix_id,
        user_id: identity.external_id,
        inherit_acquisition: true
      ).call

      assert result[:success]
      assert_equal true, result[:conversion].inherit_acquisition?
    end

    test "inherit_acquisition defaults to false" do
      result = build_service(
        event_id: event.prefix_id,
        user_id: identity.external_id
      ).call

      assert result[:success]
      assert_equal false, result[:conversion].inherit_acquisition?
    end

    test "returns error when is_acquisition true but no valid user_id" do
      result = build_service(
        event_id: event.prefix_id,
        is_acquisition: true
      ).call

      assert_not result[:success]
      assert_includes result[:errors].join.downcase, "identity"
    end

    test "creates conversion with both is_acquisition and identity" do
      result = build_service(
        event_id: event.prefix_id,
        user_id: identity.external_id,
        is_acquisition: true
      ).call

      assert result[:success]
      assert_equal identity.id, result[:conversion].identity_id
      assert_equal true, result[:conversion].is_acquisition
    end

    private

    def identity
      @identity ||= identities(:one)
    end

    def build_service(
      event_id: nil,
      visitor_id: nil,
      conversion_type: "signup",
      revenue: nil,
      currency: nil,
      properties: {},
      user_id: nil,
      is_acquisition: nil,
      inherit_acquisition: nil
    )
      Conversions::TrackingService.new(
        account,
        {
          event_id: event_id,
          visitor_id: visitor_id,
          conversion_type: conversion_type,
          revenue: revenue,
          currency: currency,
          properties: properties,
          user_id: user_id,
          is_acquisition: is_acquisition,
          inherit_acquisition: inherit_acquisition
        }.compact
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
