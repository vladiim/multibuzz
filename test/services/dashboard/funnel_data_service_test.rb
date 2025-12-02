# frozen_string_literal: true

require "test_helper"

module Dashboard
  class FunnelDataServiceTest < ActiveSupport::TestCase
    setup do
      Event.delete_all
    end

    # ==========================================
    # Basic structure tests
    # ==========================================

    test "returns success with expected data structure" do
      result = service.call

      assert result[:success]
      assert result[:data].key?(:stages)
      assert result[:data][:stages].is_a?(Array)
    end

    test "returns empty stages when no events exist" do
      result = service.call

      assert result[:success]
      assert_empty result[:data][:stages]
    end

    # ==========================================
    # Dynamic stage discovery tests
    # ==========================================

    test "discovers stages dynamically from customer event types" do
      create_events("plan_page", 5)
      create_events("pricing_click", 3)
      create_events("signup_complete", 1)

      result = service.call
      stage_names = result[:data][:stages].map { |s| s[:event_type] }

      assert_includes stage_names, "plan_page"
      assert_includes stage_names, "pricing_click"
      assert_includes stage_names, "signup_complete"
    end

    test "uses display name mapping for known event types" do
      create_events("page_view", 10)
      create_events("add_to_cart", 5)

      result = service.call
      stages = result[:data][:stages]

      visits_stage = stages.find { |s| s[:event_type] == "page_view" }
      cart_stage = stages.find { |s| s[:event_type] == "add_to_cart" }

      assert_equal "Visits", visits_stage[:stage]
      assert_equal "Add to Cart", cart_stage[:stage]
    end

    test "humanizes unknown event types for display" do
      create_events("signup_start", 5)

      result = service.call
      stage = result[:data][:stages].first

      assert_equal "signup_start", stage[:event_type]
      assert_equal "Signup Start", stage[:stage]
    end

    # ==========================================
    # Ordering tests (largest first)
    # ==========================================

    test "orders stages by count descending (largest first)" do
      create_events_with_unique_visitors("signup_complete", 2)
      create_events_with_unique_visitors("page_view", 100)
      create_events_with_unique_visitors("pricing_click", 10)

      result = service.call
      stages = result[:data][:stages]

      assert_equal "page_view", stages[0][:event_type]
      assert_equal "pricing_click", stages[1][:event_type]
      assert_equal "signup_complete", stages[2][:event_type]
    end

    # ==========================================
    # Unique users counting tests (default)
    # ==========================================

    test "counts unique visitors by default not total events" do
      # Same visitor triggers page_view 10 times
      create_events("page_view", 10)

      result = service.call
      stage = result[:data][:stages].first

      # Should count 1 unique visitor, not 10 events
      assert_equal 1, stage[:total]
    end

    test "counts multiple unique visitors correctly" do
      create_events_with_unique_visitors("page_view", 5)

      result = service.call
      stage = result[:data][:stages].first

      assert_equal 5, stage[:total]
    end

    # ==========================================
    # Total events counting tests (optional)
    # ==========================================

    test "counts total events when unique_users is false" do
      # Same visitor triggers page_view 10 times
      create_events("page_view", 10)

      result = service(unique_users: false).call
      stage = result[:data][:stages].first

      assert_equal 10, stage[:total]
    end

    # ==========================================
    # Stage totals tests
    # ==========================================

    test "calculates unique users per stage" do
      create_events_with_unique_visitors("page_view", 10)
      create_events_with_unique_visitors("add_to_cart", 5)

      result = service.call
      stages = result[:data][:stages]

      visits_stage = stages.find { |s| s[:event_type] == "page_view" }
      add_to_cart_stage = stages.find { |s| s[:event_type] == "add_to_cart" }

      assert_equal 10, visits_stage[:total]
      assert_equal 5, add_to_cart_stage[:total]
    end

    # ==========================================
    # By channel breakdown tests
    # ==========================================

    test "breaks down unique users by channel" do
      create_events_with_unique_visitors("page_view", 5, channel: Channels::PAID_SEARCH)
      create_events_with_unique_visitors("page_view", 3, channel: Channels::EMAIL)

      result = service.call
      visits_stage = result[:data][:stages].find { |s| s[:event_type] == "page_view" }

      assert_equal 5, visits_stage[:by_channel][Channels::PAID_SEARCH]
      assert_equal 3, visits_stage[:by_channel][Channels::EMAIL]
    end

    test "returns zero for channels with no events" do
      create_events_with_unique_visitors("page_view", 5, channel: Channels::PAID_SEARCH)

      result = service.call
      visits_stage = result[:data][:stages].find { |s| s[:event_type] == "page_view" }

      assert_equal 0, visits_stage[:by_channel][Channels::DIRECT]
    end

    # ==========================================
    # Conversion rate tests
    # ==========================================

    test "calculates conversion rate from previous stage" do
      create_events_with_unique_visitors("page_view", 100)
      create_events_with_unique_visitors("add_to_cart", 10)

      result = service.call
      # page_view is first (100 users), add_to_cart is second (10 users)
      add_to_cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      # 10 / 100 = 10%
      assert_equal 10.0, add_to_cart_stage[:conversion_rate]
    end

    test "first stage has nil conversion rate" do
      create_events_with_unique_visitors("page_view", 100)

      result = service.call
      visits_stage = result[:data][:stages].first

      assert_nil visits_stage[:conversion_rate]
    end

    test "handles single stage gracefully" do
      create_events_with_unique_visitors("add_to_cart", 10)

      result = service.call
      stage = result[:data][:stages].first

      # First stage always has nil conversion rate
      assert_nil stage[:conversion_rate]
    end

    # ==========================================
    # Filter tests - date range
    # ==========================================

    test "filters by date range" do
      create_events_with_unique_visitors("page_view", 5, occurred_at: 5.days.ago)
      create_events_with_unique_visitors("page_view", 3, occurred_at: 15.days.ago)

      result = service(date_range: "7d").call
      visits_stage = result[:data][:stages].find { |s| s[:event_type] == "page_view" }

      assert_equal 5, visits_stage[:total]
    end

    # ==========================================
    # Filter tests - channels
    # ==========================================

    test "filters by selected channels" do
      create_events_with_unique_visitors("page_view", 5, channel: Channels::PAID_SEARCH)
      create_events_with_unique_visitors("page_view", 3, channel: Channels::EMAIL)

      result = service(channels: [Channels::PAID_SEARCH]).call
      visits_stage = result[:data][:stages].find { |s| s[:event_type] == "page_view" }

      assert_equal 5, visits_stage[:total]
      assert_equal 5, visits_stage[:by_channel][Channels::PAID_SEARCH]
      assert_equal 0, visits_stage[:by_channel][Channels::EMAIL]
    end

    # ==========================================
    # Environment scope tests
    # ==========================================

    test "only includes production events by default" do
      create_events_with_unique_visitors("page_view", 5, is_test: false)
      create_events_with_unique_visitors("page_view", 3, is_test: true)

      result = service.call
      visits_stage = result[:data][:stages].find { |s| s[:event_type] == "page_view" }

      assert_equal 5, visits_stage[:total]
    end

    # ==========================================
    # Multi-account isolation tests
    # ==========================================

    test "only includes events for specified account" do
      create_events_with_unique_visitors("page_view", 5)

      # Create events for different account
      other_account = accounts(:two)
      other_visitor = visitors(:three)
      other_session = other_account.sessions.create!(
        session_id: "other_session",
        visitor: other_visitor,
        started_at: Time.current,
        channel: Channels::DIRECT
      )
      3.times do
        other_account.events.create!(
          visitor: other_visitor,
          session: other_session,
          event_type: "page_view",
          occurred_at: Time.current,
          properties: { url: "https://example.com" }
        )
      end

      result = service.call
      visits_stage = result[:data][:stages].find { |s| s[:event_type] == "page_view" }

      assert_equal 5, visits_stage[:total]
    end

    private

    def service(date_range: "30d", channels: Channels::ALL, unique_users: true)
      filter_params = {
        date_range: date_range,
        models: [attribution_models(:first_touch)],
        channels: channels,
        journey_position: "last_touch",
        metric: "conversions",
        unique_users: unique_users
      }
      Dashboard::FunnelDataService.new(account, filter_params)
    end

    def account
      @account ||= accounts(:one)
    end

    # Creates multiple events for the SAME visitor (tests unique counting)
    def create_events(event_type, count, channel: Channels::PAID_SEARCH, occurred_at: Time.current, is_test: false)
      session = account.sessions.create!(
        session_id: "session_#{SecureRandom.hex(4)}",
        visitor: visitors(:one),
        started_at: occurred_at,
        channel: channel,
        is_test: is_test
      )

      count.times do
        account.events.create!(
          visitor: visitors(:one),
          session: session,
          event_type: event_type,
          occurred_at: occurred_at,
          is_test: is_test,
          properties: { url: "https://example.com/#{event_type}" }
        )
      end
    end

    # Creates events with UNIQUE visitors (each event = different visitor)
    def create_events_with_unique_visitors(event_type, count, channel: Channels::PAID_SEARCH, occurred_at: Time.current, is_test: false)
      count.times do |i|
        visitor = account.visitors.create!(
          visitor_id: "visitor_#{event_type}_#{SecureRandom.hex(4)}_#{i}"
        )

        session = account.sessions.create!(
          session_id: "session_#{SecureRandom.hex(4)}_#{i}",
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
          properties: { url: "https://example.com/#{event_type}" }
        )
      end
    end
  end

  # ==========================================
  # Caching tests
  # ==========================================

  class FunnelCachingTest < ActiveSupport::TestCase
    setup do
      Event.delete_all
    end

    test "caches results on first call" do
      create_events_with_unique_visitors("page_view", 5)

      assert_difference -> { cache_writes }, 1 do
        service.call
      end
    end

    test "returns cached results on second call" do
      create_events_with_unique_visitors("page_view", 5)
      service.call

      assert_no_difference -> { cache_writes } do
        result = service.call
        visits_stage = result[:data][:stages].find { |s| s[:event_type] == "page_view" }
        assert_equal 5, visits_stage[:total]
      end
    end

    test "cache is invalidated when events change" do
      create_events_with_unique_visitors("page_view", 5)
      service.call # populate cache

      # Create new events via a new session (simulating new data)
      create_events_with_unique_visitors("page_view", 3)

      # Clear cache manually (in real app, this happens via invalidation)
      Dashboard::CacheInvalidator.new(account).call

      # Next call should hit DB with new data
      result = service.call
      visits_stage = result[:data][:stages].find { |s| s[:event_type] == "page_view" }
      assert_equal 8, visits_stage[:total]
    end

    test "different filter params use different cache keys" do
      create_events_with_unique_visitors("page_view", 5)

      service_7d = service(date_range: "7d")
      service_30d = service(date_range: "30d")

      # Both should cache separately
      assert_difference -> { cache_writes }, 2 do
        service_7d.call
        service_30d.call
      end
    end

    test "different channel filters use different cache keys" do
      create_events_with_unique_visitors("page_view", 5, channel: Channels::PAID_SEARCH)
      create_events_with_unique_visitors("page_view", 3, channel: Channels::EMAIL)

      service_all = service(channels: Channels::ALL)
      service_paid = service(channels: [Channels::PAID_SEARCH])

      # Both should cache separately
      assert_difference -> { cache_writes }, 2 do
        service_all.call
        service_paid.call
      end
    end

    private

    def service(date_range: "30d", channels: Channels::ALL)
      filter_params = {
        date_range: date_range,
        models: [attribution_models(:first_touch)],
        channels: channels,
        journey_position: "last_touch",
        metric: "conversions",
        unique_users: true
      }
      Dashboard::FunnelDataService.new(account, filter_params)
    end

    def account
      @account ||= accounts(:one)
    end

    def cache_writes
      Rails.cache.instance_variable_get(:@data)&.size || 0
    end

    # Creates events with UNIQUE visitors (each event = different visitor)
    def create_events_with_unique_visitors(event_type, count, channel: Channels::PAID_SEARCH, occurred_at: Time.current, is_test: false)
      count.times do |i|
        visitor = account.visitors.create!(
          visitor_id: "visitor_#{event_type}_#{SecureRandom.hex(4)}_#{i}"
        )

        session = account.sessions.create!(
          session_id: "session_#{SecureRandom.hex(4)}_#{i}",
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
          properties: { url: "https://example.com/#{event_type}" }
        )
      end
    end
  end
end
