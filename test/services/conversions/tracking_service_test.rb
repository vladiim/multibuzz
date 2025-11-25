# frozen_string_literal: true

require "test_helper"

module Conversions
  class TrackingServiceTest < ActiveSupport::TestCase
    test "creates conversion from valid event" do
      result = service.call

      assert result[:success]
      assert_instance_of Conversion, result[:conversion]
      assert_equal "signup", result[:conversion].conversion_type
      assert_equal event.visitor_id, result[:conversion].visitor_id
      assert_equal event.session_id, result[:conversion].session_id
      assert_equal event.id, result[:conversion].event_id
    end

    test "returns error for missing event_id" do
      result = build_service(event_id: nil).call

      assert_not result[:success]
      assert_includes result[:errors], "event_id is required"
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

    test "returns error for missing conversion_type" do
      result = build_service(conversion_type: nil).call

      assert_not result[:success]
      assert_includes result[:errors], "conversion_type is required"
    end

    test "stores revenue when provided" do
      result = build_service(revenue: 99.99).call

      assert result[:success]
      assert_equal 99.99, result[:conversion].revenue.to_f
    end

    test "sets converted_at from event occurred_at" do
      result = service.call

      assert result[:success]
      assert_equal event.occurred_at, result[:conversion].converted_at
    end

    test "triggers attribution calculation" do
      result = service.call

      assert result[:success]
      assert_not_nil result[:attribution_credits]
    end

    private

    def service
      @service ||= build_service
    end

    def build_service(event_id: event.prefix_id, conversion_type: "signup", revenue: nil)
      Conversions::TrackingService.new(
        account,
        {
          event_id: event_id,
          conversion_type: conversion_type,
          revenue: revenue
        }
      )
    end

    def account
      @account ||= accounts(:one)
    end

    def event
      @event ||= events(:one)
    end
  end
end
