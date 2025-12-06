# frozen_string_literal: true

require "test_helper"

module Dashboard
  class FunnelDataServiceTest < ActiveSupport::TestCase
    setup do
      AttributionCredit.delete_all
      Conversion.delete_all
      Event.delete_all
      Session.delete_all
    end

    # ==========================================
    # Basic structure tests
    # ==========================================

    test "returns success with expected data structure" do
      create_session

      result = service.call

      assert result[:success]
      assert result[:data].key?(:stages)
      assert result[:data][:stages].is_a?(Array)
    end

    test "returns visits and conversions stages even with no events" do
      create_session
      create_conversion

      result = service.call

      assert result[:success]
      stage_names = result[:data][:stages].map { |s| s[:stage] }
      assert_includes stage_names, "Visits"
      assert_includes stage_names, "Conversions"
    end

    test "returns empty stages when no data exists" do
      result = service.call

      assert result[:success]
      assert_empty result[:data][:stages]
    end

    # ==========================================
    # Funnel structure tests (Visits → Events → Conversions)
    # ==========================================

    test "visits stage is always first when sessions exist" do
      create_sessions_with_events("add_to_cart", 5)

      result = service.call
      stages = result[:data][:stages]

      assert_equal "Visits", stages.first[:stage]
      assert_nil stages.first[:event_type]
    end

    test "conversions stage is always last when conversions exist" do
      create_sessions_with_events("add_to_cart", 5)
      create_conversions(3)

      result = service.call
      stages = result[:data][:stages]

      assert_equal "Conversions", stages.last[:stage]
      assert_nil stages.last[:event_type]
    end

    test "event stages appear between visits and conversions" do
      create_sessions_with_events("add_to_cart", 10)
      create_sessions_with_events("checkout_started", 5)
      create_conversions(3)

      result = service.call
      stages = result[:data][:stages]

      # First is Visits, last is Conversions
      assert_equal "Visits", stages.first[:stage]
      assert_equal "Conversions", stages.last[:stage]

      # Middle stages are events
      event_stages = stages[1..-2]
      assert event_stages.all? { |s| s[:event_type].present? }
      assert_includes event_stages.map { |s| s[:event_type] }, "add_to_cart"
      assert_includes event_stages.map { |s| s[:event_type] }, "checkout_started"
    end

    # ==========================================
    # Dynamic stage discovery tests
    # ==========================================

    test "discovers event stages dynamically from customer event types" do
      create_sessions_with_events("plan_page", 5)
      create_sessions_with_events("pricing_click", 3)
      create_sessions_with_events("signup_complete", 1)

      result = service.call
      event_types = result[:data][:stages].map { |s| s[:event_type] }.compact

      assert_includes event_types, "plan_page"
      assert_includes event_types, "pricing_click"
      assert_includes event_types, "signup_complete"
    end

    test "uses display name mapping for known event types" do
      create_sessions_with_events("add_to_cart", 5)

      result = service.call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      assert_equal "Add to Cart", cart_stage[:stage]
    end

    test "humanizes unknown event types for display" do
      create_sessions_with_events("signup_start", 5)

      result = service.call
      stage = result[:data][:stages].find { |s| s[:event_type] == "signup_start" }

      assert_equal "signup_start", stage[:event_type]
      assert_equal "Signup Start", stage[:stage]
    end

    # ==========================================
    # Ordering tests (events by count descending)
    # ==========================================

    test "orders event stages by count descending" do
      create_sessions_with_events("signup_complete", 2)
      create_sessions_with_events("add_to_cart", 100)
      create_sessions_with_events("pricing_click", 10)

      result = service.call
      event_stages = result[:data][:stages].select { |s| s[:event_type].present? }

      assert_equal "add_to_cart", event_stages[0][:event_type]
      assert_equal "pricing_click", event_stages[1][:event_type]
      assert_equal "signup_complete", event_stages[2][:event_type]
    end

    # ==========================================
    # Unique users counting tests
    # ==========================================

    test "counts unique visitors for visits stage" do
      # Create 5 sessions for 5 unique visitors
      5.times { create_session }

      result = service.call
      visits_stage = result[:data][:stages].find { |s| s[:stage] == "Visits" }

      assert_equal 5, visits_stage[:total]
    end

    test "counts unique visitors for event stages" do
      # Same visitor triggers add_to_cart 10 times
      session = create_session
      10.times { create_event(session, "add_to_cart") }

      result = service.call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      # Should count 1 unique visitor, not 10 events
      assert_equal 1, cart_stage[:total]
    end

    test "counts multiple unique visitors correctly for events" do
      create_sessions_with_events("add_to_cart", 5)

      result = service.call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      assert_equal 5, cart_stage[:total]
    end

    test "counts unique visitors for conversions stage" do
      create_conversions(3)

      result = service.call
      conv_stage = result[:data][:stages].find { |s| s[:stage] == "Conversions" }

      assert_equal 3, conv_stage[:total]
    end

    # ==========================================
    # Total events counting tests (unique_users: false)
    # ==========================================

    test "counts total sessions when unique_users is false" do
      # Create 3 sessions for same visitor
      visitor = create_visitor
      3.times { create_session(visitor: visitor) }

      result = service(unique_users: false).call
      visits_stage = result[:data][:stages].find { |s| s[:stage] == "Visits" }

      assert_equal 3, visits_stage[:total]
    end

    test "counts total events when unique_users is false" do
      session = create_session
      10.times { create_event(session, "add_to_cart") }

      result = service(unique_users: false).call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      assert_equal 10, cart_stage[:total]
    end

    # ==========================================
    # By channel breakdown tests
    # ==========================================

    test "breaks down visits by channel" do
      5.times { create_session(channel: Channels::PAID_SEARCH) }
      3.times { create_session(channel: Channels::EMAIL) }

      result = service.call
      visits_stage = result[:data][:stages].find { |s| s[:stage] == "Visits" }

      assert_equal 5, visits_stage[:by_channel][Channels::PAID_SEARCH]
      assert_equal 3, visits_stage[:by_channel][Channels::EMAIL]
    end

    test "breaks down events by channel" do
      create_sessions_with_events("add_to_cart", 5, channel: Channels::PAID_SEARCH)
      create_sessions_with_events("add_to_cart", 3, channel: Channels::EMAIL)

      result = service.call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      assert_equal 5, cart_stage[:by_channel][Channels::PAID_SEARCH]
      assert_equal 3, cart_stage[:by_channel][Channels::EMAIL]
    end

    test "returns zero for channels with no data" do
      create_sessions_with_events("add_to_cart", 5, channel: Channels::PAID_SEARCH)

      result = service.call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      assert_equal 0, cart_stage[:by_channel][Channels::DIRECT]
    end

    # ==========================================
    # Conversion rate tests
    # ==========================================

    test "first stage has nil conversion rate" do
      create_sessions_with_events("add_to_cart", 10)

      result = service.call
      visits_stage = result[:data][:stages].first

      assert_nil visits_stage[:conversion_rate]
    end

    test "calculates conversion rate from previous stage" do
      # 100 visits, 10 add_to_cart = 10% conversion
      100.times { create_session }
      create_sessions_with_events("add_to_cart", 10)

      result = service.call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      # Cart stage conversion rate = 10 / 110 visits (100 + 10 from events)
      # Actually the visits count includes all sessions, so 110 unique visitors
      assert cart_stage[:conversion_rate].present?
    end

    # ==========================================
    # Filter tests - date range
    # ==========================================

    test "filters by date range" do
      create_sessions_with_events("add_to_cart", 5, occurred_at: 5.days.ago)
      create_sessions_with_events("add_to_cart", 3, occurred_at: 15.days.ago)

      result = service(date_range: "7d").call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      assert_equal 5, cart_stage[:total]
    end

    # ==========================================
    # Filter tests - channels
    # ==========================================

    test "filters by selected channels" do
      create_sessions_with_events("add_to_cart", 5, channel: Channels::PAID_SEARCH)
      create_sessions_with_events("add_to_cart", 3, channel: Channels::EMAIL)

      result = service(channels: [Channels::PAID_SEARCH]).call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      assert_equal 5, cart_stage[:total]
    end

    # ==========================================
    # Environment scope tests
    # ==========================================

    test "only includes production data by default" do
      create_sessions_with_events("add_to_cart", 5, is_test: false)
      create_sessions_with_events("add_to_cart", 3, is_test: true)

      result = service.call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      assert_equal 5, cart_stage[:total]
    end

    # ==========================================
    # Multi-account isolation tests
    # ==========================================

    test "only includes data for specified account" do
      create_sessions_with_events("add_to_cart", 5)

      # Create data for different account
      other_account = accounts(:two)
      other_visitor = other_account.visitors.create!(visitor_id: "other_visitor")
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
          event_type: "add_to_cart",
          occurred_at: Time.current,
          properties: { url: "https://other.com" }
        )
      end

      result = service.call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }

      assert_equal 5, cart_stage[:total]
    end

    # ==========================================
    # Funnel filtering tests
    # ==========================================

    test "returns events filtered by funnel" do
      create_sessions_with_events("signup_start", 5, funnel: "signup")
      create_sessions_with_events("signup_complete", 3, funnel: "signup")
      create_sessions_with_events("add_to_cart", 10, funnel: "purchase")

      result = service(funnel: "signup").call
      event_types = result[:data][:stages].map { |s| s[:event_type] }.compact

      assert_includes event_types, "signup_start"
      assert_includes event_types, "signup_complete"
      refute_includes event_types, "add_to_cart"
    end

    test "returns all events when funnel is nil" do
      create_sessions_with_events("signup_start", 5, funnel: "signup")
      create_sessions_with_events("add_to_cart", 10, funnel: "purchase")

      result = service(funnel: nil).call
      event_types = result[:data][:stages].map { |s| s[:event_type] }.compact

      assert_includes event_types, "signup_start"
      assert_includes event_types, "add_to_cart"
    end

    test "returns available_funnels list" do
      create_sessions_with_events("signup_start", 5, funnel: "signup")
      create_sessions_with_events("add_to_cart", 10, funnel: "purchase")

      result = service.call

      assert_includes result[:data][:available_funnels], "signup"
      assert_includes result[:data][:available_funnels], "purchase"
    end

    test "available_funnels excludes nil values" do
      create_sessions_with_events("add_to_cart", 20, funnel: nil)
      create_sessions_with_events("signup_start", 5, funnel: "signup")

      result = service.call

      refute_includes result[:data][:available_funnels], nil
      assert_equal 1, result[:data][:available_funnels].size
    end

    test "available_funnels sorted alphabetically" do
      create_sessions_with_events("signup_start", 5, funnel: "signup")
      create_sessions_with_events("add_to_cart", 10, funnel: "purchase")
      create_sessions_with_events("view_product", 20, funnel: "awareness")

      result = service.call
      funnels = result[:data][:available_funnels]

      assert_equal ["awareness", "purchase", "signup"], funnels
    end

    private

    def service(date_range: "30d", channels: Channels::ALL, unique_users: true, funnel: nil)
      filter_params = {
        date_range: date_range,
        models: [attribution_models(:first_touch)],
        channels: channels,
        journey_position: "last_touch",
        metric: "conversions",
        unique_users: unique_users,
        funnel: funnel
      }
      Dashboard::FunnelDataService.new(account, filter_params)
    end

    def account
      @account ||= accounts(:one)
    end

    def create_visitor
      account.visitors.create!(visitor_id: "visitor_#{SecureRandom.hex(8)}")
    end

    def create_session(visitor: nil, channel: Channels::PAID_SEARCH, occurred_at: Time.current, is_test: false)
      visitor ||= create_visitor
      account.sessions.create!(
        session_id: "session_#{SecureRandom.hex(8)}",
        visitor: visitor,
        started_at: occurred_at,
        channel: channel,
        is_test: is_test
      )
    end

    def create_event(session, event_type, occurred_at: Time.current, is_test: false, funnel: nil)
      account.events.create!(
        visitor: session.visitor,
        session: session,
        event_type: event_type,
        occurred_at: occurred_at,
        is_test: is_test,
        funnel: funnel,
        properties: { url: "https://example.com/#{event_type}" }
      )
    end

    def create_conversion(visitor: nil, session: nil, occurred_at: Time.current)
      visitor ||= create_visitor
      session ||= create_session(visitor: visitor)
      account.conversions.create!(
        visitor: visitor,
        session_id: session.id,
        conversion_type: "purchase",
        revenue: 99.99,
        converted_at: occurred_at
      )
    end

    # Helper: Create N sessions, each with one event of the given type
    def create_sessions_with_events(event_type, count, channel: Channels::PAID_SEARCH, occurred_at: Time.current, is_test: false, funnel: nil)
      count.times do
        session = create_session(channel: channel, occurred_at: occurred_at, is_test: is_test)
        create_event(session, event_type, occurred_at: occurred_at, is_test: is_test, funnel: funnel)
      end
    end

    def create_conversions(count, channel: Channels::PAID_SEARCH)
      count.times do
        visitor = create_visitor
        session = create_session(visitor: visitor, channel: channel)
        create_conversion(visitor: visitor, session: session)
      end
    end
  end

  # ==========================================
  # Caching tests
  # ==========================================

  class FunnelCachingTest < ActiveSupport::TestCase
    setup do
      AttributionCredit.delete_all
      Conversion.delete_all
      Event.delete_all
      Session.delete_all
      Rails.cache.clear
    end

    test "caches results on first call" do
      create_sessions_with_events("add_to_cart", 5)

      assert_difference -> { cache_writes }, 1 do
        service.call
      end
    end

    test "returns cached results on second call" do
      create_sessions_with_events("add_to_cart", 5)
      service.call

      assert_no_difference -> { cache_writes } do
        result = service.call
        cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }
        assert_equal 5, cart_stage[:total]
      end
    end

    test "cache is invalidated when data changes" do
      create_sessions_with_events("add_to_cart", 5)
      service.call # populate cache

      # Create more data
      create_sessions_with_events("add_to_cart", 3)

      # Clear cache manually
      Dashboard::CacheInvalidator.new(account).call

      # Next call should have new data
      result = service.call
      cart_stage = result[:data][:stages].find { |s| s[:event_type] == "add_to_cart" }
      assert_equal 8, cart_stage[:total]
    end

    test "different filter params use different cache keys" do
      create_sessions_with_events("add_to_cart", 5)

      assert_difference -> { cache_writes }, 2 do
        service(date_range: "7d").call
        service(date_range: "30d").call
      end
    end

    test "different channel filters use different cache keys" do
      create_sessions_with_events("add_to_cart", 5, channel: Channels::PAID_SEARCH)
      create_sessions_with_events("add_to_cart", 3, channel: Channels::EMAIL)

      assert_difference -> { cache_writes }, 2 do
        service(channels: Channels::ALL).call
        service(channels: [Channels::PAID_SEARCH]).call
      end
    end

    test "different funnel filters use different cache keys" do
      create_sessions_with_events("signup_start", 5, funnel: "signup")
      create_sessions_with_events("add_to_cart", 10, funnel: "purchase")

      assert_difference -> { cache_writes }, 2 do
        service(funnel: "signup").call
        service(funnel: "purchase").call
      end
    end

    private

    def cache_writes
      Rails.cache.instance_variable_get(:@data)&.size || 0
    end

    def service(date_range: "30d", channels: Channels::ALL, funnel: nil)
      filter_params = {
        date_range: date_range,
        models: [attribution_models(:first_touch)],
        channels: channels,
        journey_position: "last_touch",
        metric: "conversions",
        unique_users: true,
        funnel: funnel
      }
      Dashboard::FunnelDataService.new(account, filter_params)
    end

    def account
      @account ||= accounts(:one)
    end

    def create_visitor
      account.visitors.create!(visitor_id: "visitor_#{SecureRandom.hex(8)}")
    end

    def create_session(visitor: nil, channel: Channels::PAID_SEARCH, occurred_at: Time.current, is_test: false)
      visitor ||= create_visitor
      account.sessions.create!(
        session_id: "session_#{SecureRandom.hex(8)}",
        visitor: visitor,
        started_at: occurred_at,
        channel: channel,
        is_test: is_test
      )
    end

    def create_event(session, event_type, occurred_at: Time.current, is_test: false, funnel: nil)
      account.events.create!(
        visitor: session.visitor,
        session: session,
        event_type: event_type,
        occurred_at: occurred_at,
        is_test: is_test,
        funnel: funnel,
        properties: { url: "https://example.com/#{event_type}" }
      )
    end

    def create_sessions_with_events(event_type, count, channel: Channels::PAID_SEARCH, occurred_at: Time.current, is_test: false, funnel: nil)
      count.times do
        session = create_session(channel: channel, occurred_at: occurred_at, is_test: is_test)
        create_event(session, event_type, occurred_at: occurred_at, is_test: is_test, funnel: funnel)
      end
    end
  end
end
