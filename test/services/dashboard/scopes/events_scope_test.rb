# frozen_string_literal: true

require "test_helper"

module Dashboard
  module Scopes
    class EventsScopeTest < ActiveSupport::TestCase
      setup do
        Event.delete_all
      end

      # ==========================================
      # Funnel filtering tests
      # ==========================================

      test "filters events by funnel when funnel param provided" do
        create_event("signup_start", funnel: "signup")
        create_event("signup_complete", funnel: "signup")
        create_event("add_to_cart", funnel: "purchase")

        result = scope(funnel: "signup").call

        event_types = result.pluck(:event_type)

        assert_includes event_types, "signup_start"
        assert_includes event_types, "signup_complete"
        refute_includes event_types, "add_to_cart"
      end

      test "returns all events when funnel is nil" do
        create_event("signup_start", funnel: "signup")
        create_event("add_to_cart", funnel: "purchase")
        create_event("page_view", funnel: nil)

        result = scope(funnel: nil).call

        assert_equal 3, result.count
      end

      test "returns all events when funnel is 'all'" do
        create_event("signup_start", funnel: "signup")
        create_event("add_to_cart", funnel: "purchase")
        create_event("page_view", funnel: nil)

        result = scope(funnel: "all").call

        assert_equal 3, result.count
      end

      test "excludes events from other funnels" do
        create_event("signup_start", funnel: "signup")
        create_event("add_to_cart", funnel: "purchase")

        result = scope(funnel: "signup").call

        assert_equal 1, result.count
        assert_equal "signup_start", result.first.event_type
      end

      test "includes events with nil funnel only in all view" do
        create_event("page_view", funnel: nil)
        create_event("signup_start", funnel: "signup")

        # "all" view includes nil funnel events
        all_result = scope(funnel: nil).call

        assert_equal 2, all_result.count

        # specific funnel excludes nil funnel events
        signup_result = scope(funnel: "signup").call

        assert_equal 1, signup_result.count
        assert_equal "signup_start", signup_result.first.event_type
      end

      # ==========================================
      # Existing filter tests (ensure no regression)
      # ==========================================

      test "filters by date range" do
        create_event("page_view", occurred_at: 5.days.ago)
        create_event("page_view", occurred_at: 15.days.ago)

        result = scope(date_range: "7d").call

        assert_equal 1, result.count
      end

      test "filters by channels" do
        create_event("page_view", channel: Channels::PAID_SEARCH)
        create_event("page_view", channel: Channels::EMAIL)

        result = scope(channels: [ Channels::PAID_SEARCH ]).call

        assert_equal 1, result.count
      end

      test "only includes production events by default" do
        create_event("page_view", is_test: false)
        create_event("page_view", is_test: true)

        result = scope.call

        assert_equal 1, result.count
      end

      test "combines funnel filter with other filters" do
        create_event("signup_start", funnel: "signup", channel: Channels::PAID_SEARCH)
        create_event("signup_start", funnel: "signup", channel: Channels::EMAIL)
        create_event("add_to_cart", funnel: "purchase", channel: Channels::PAID_SEARCH)

        result = scope(funnel: "signup", channels: [ Channels::PAID_SEARCH ]).call

        assert_equal 1, result.count
        assert_equal "signup_start", result.first.event_type
      end

      private

      def scope(date_range: "30d", channels: Channels::ALL, funnel: nil)
        Dashboard::Scopes::EventsScope.new(
          account: account,
          date_range: Dashboard::DateRangeParser.new(date_range),
          channels: channels,
          funnel: funnel
        )
      end

      def account
        @account ||= accounts(:one)
      end

      def create_event(event_type, funnel: nil, channel: Channels::PAID_SEARCH, occurred_at: Time.current, is_test: false)
        visitor = account.visitors.create!(
          visitor_id: "visitor_#{SecureRandom.hex(4)}"
        )

        session = account.sessions.create!(
          session_id: "session_#{SecureRandom.hex(4)}",
          visitor: visitor,
          started_at: occurred_at,
          channel: channel,
          is_test: is_test
        )

        account.events.create!(
          visitor: visitor,
          session: session,
          event_type: event_type,
          occurred_at: occurred_at,
          is_test: is_test,
          funnel: funnel,
          properties: { url: "https://example.com/#{event_type}" }
        )
      end
    end
  end
end
