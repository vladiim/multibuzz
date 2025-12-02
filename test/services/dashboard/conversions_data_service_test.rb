# frozen_string_literal: true

require "test_helper"

module Dashboard
  class ConversionsDataServiceTest < ActiveSupport::TestCase
    setup do
      # Clear fixture data to ensure clean slate for each test
      AttributionCredit.delete_all
      Conversion.where(account: account).where.not(id: [conversions(:signup).id, conversions(:purchase).id]).delete_all
    end

    # ==========================================
    # Basic structure tests
    # ==========================================

    test "returns success with expected data structure" do
      result = service.call

      assert result[:success]
      assert result[:data].key?(:totals)
      assert result[:data].key?(:by_channel)
      assert result[:data].key?(:time_series)
      assert result[:data].key?(:top_campaigns)
    end

    test "totals include required metrics" do
      result = service.call
      totals = result[:data][:totals]

      assert totals.key?(:conversions)
      assert totals.key?(:revenue)
      assert totals.key?(:conversion_rate)
      assert totals.key?(:aov)
      assert totals.key?(:prior_period)
    end

    # ==========================================
    # Totals calculation tests
    # ==========================================

    test "calculates total conversions from attribution credits" do
      create_test_credits

      result = service.call
      totals = result[:data][:totals]

      # 3 credits with credit values 1.0, 0.5, 0.5 = 2.0 total conversions
      assert_equal 2.0, totals[:conversions]
    end

    test "calculates total revenue from attribution credits" do
      create_test_credits

      result = service.call
      totals = result[:data][:totals]

      # Credits with revenue 100, 50, 50 = 200 total
      assert_equal 200.0, totals[:revenue]
    end

    test "calculates average order value" do
      create_test_credits

      result = service.call
      totals = result[:data][:totals]

      # Revenue 200 / Conversions 2.0 = 100.0 AOV
      assert_equal 100.0, totals[:aov]
    end

    test "handles zero conversions gracefully" do
      # No credits created
      result = service.call
      totals = result[:data][:totals]

      assert_equal 0, totals[:conversions]
      assert_equal 0, totals[:revenue]
      assert_nil totals[:aov]
      assert_nil totals[:conversion_rate]
    end

    # ==========================================
    # Prior period comparison tests
    # ==========================================

    test "calculates prior period totals" do
      create_test_credits
      create_prior_period_credits

      result = service.call
      prior = result[:data][:totals][:prior_period]

      assert prior[:conversions].present?
      assert prior[:revenue].present?
    end

    # ==========================================
    # By channel breakdown tests
    # ==========================================

    test "groups credits by channel" do
      create_test_credits

      result = service.call
      by_channel = result[:data][:by_channel]

      assert by_channel.is_a?(Array)
      channels = by_channel.map { |c| c[:channel] }
      assert_includes channels, Channels::PAID_SEARCH
      assert_includes channels, Channels::EMAIL
    end

    test "calculates credits and revenue per channel" do
      create_test_credits

      result = service.call
      by_channel = result[:data][:by_channel]

      paid_search = by_channel.find { |c| c[:channel] == Channels::PAID_SEARCH }
      assert_equal 1.0, paid_search[:credits]
      assert_equal 100.0, paid_search[:revenue]
    end

    test "calculates percentage per channel" do
      create_test_credits

      result = service.call
      by_channel = result[:data][:by_channel]

      paid_search = by_channel.find { |c| c[:channel] == Channels::PAID_SEARCH }
      # 1.0 credit out of 2.0 total = 50%
      assert_equal 50.0, paid_search[:percentage]
    end

    test "sorts channels by credits descending" do
      create_test_credits

      result = service.call
      by_channel = result[:data][:by_channel]

      credits = by_channel.map { |c| c[:credits] }
      assert_equal credits.sort.reverse, credits
    end

    # ==========================================
    # Filter tests - date range
    # ==========================================

    test "filters by date range 7d" do
      create_credit_at(8.days.ago) # Outside range
      create_credit_at(5.days.ago) # Inside range

      result = service(date_range: "7d").call
      totals = result[:data][:totals]

      assert_equal 1.0, totals[:conversions]
    end

    test "filters by date range 30d" do
      create_credit_at(35.days.ago) # Outside range
      create_credit_at(15.days.ago) # Inside range

      result = service(date_range: "30d").call
      totals = result[:data][:totals]

      assert_equal 1.0, totals[:conversions]
    end

    test "filters by custom date range" do
      create_credit_at(10.days.ago)
      create_credit_at(5.days.ago)

      custom_range = {
        start_date: 7.days.ago.to_date.to_s,
        end_date: Date.current.to_s
      }

      result = service(date_range: custom_range).call
      totals = result[:data][:totals]

      assert_equal 1.0, totals[:conversions]
    end

    # ==========================================
    # Filter tests - channels
    # ==========================================

    test "filters by selected channels" do
      create_test_credits # Creates paid_search and email credits

      result = service(channels: [Channels::PAID_SEARCH]).call
      by_channel = result[:data][:by_channel]

      channels = by_channel.map { |c| c[:channel] }
      assert_includes channels, Channels::PAID_SEARCH
      assert_not_includes channels, Channels::EMAIL
    end

    # ==========================================
    # Filter tests - attribution model
    # ==========================================

    test "filters by attribution model" do
      other_model = account.attribution_models.create!(
        name: "Other Model",
        algorithm: :linear,
        is_active: true
      )
      create_credit_for_model(first_touch_model)
      create_credit_for_model(other_model)

      result = service(models: [first_touch_model]).call
      totals = result[:data][:totals]

      assert_equal 1.0, totals[:conversions]
    end

    # ==========================================
    # Time series tests
    # ==========================================

    test "returns time series with dates and series" do
      create_test_credits

      result = service.call
      time_series = result[:data][:time_series]

      assert time_series[:dates].is_a?(Array)
      assert time_series[:series].is_a?(Array)
    end

    test "time series covers date range" do
      result = service(date_range: "7d").call
      time_series = result[:data][:time_series]

      assert_equal 7, time_series[:dates].length
    end

    # ==========================================
    # Top campaigns tests
    # ==========================================

    test "returns top campaigns grouped by channel" do
      create_credit_with_campaign(Channels::PAID_SEARCH, "Campaign A")
      create_credit_with_campaign(Channels::PAID_SEARCH, "Campaign B")

      result = service.call
      top_campaigns = result[:data][:top_campaigns]

      assert top_campaigns.key?(Channels::PAID_SEARCH)
      campaign_names = top_campaigns[Channels::PAID_SEARCH].map { |c| c[:name] }
      assert_includes campaign_names, "Campaign A"
    end

    # ==========================================
    # Environment scope tests
    # ==========================================

    test "only includes production credits by default" do
      create_credit(is_test: false)
      create_credit(is_test: true)

      result = service.call
      totals = result[:data][:totals]

      assert_equal 1.0, totals[:conversions]
    end

    # ==========================================
    # Multi-account isolation tests
    # ==========================================

    test "only includes credits for specified account" do
      create_test_credits

      # Create credit for different account
      other_account = accounts(:two)
      other_model = other_account.attribution_models.first
      other_conversion = other_account.conversions.create!(
        visitor: visitors(:three),
        conversion_type: "signup",
        converted_at: Time.current
      )
      other_account.attribution_credits.create!(
        conversion: other_conversion,
        attribution_model: other_model,
        session_id: 999,
        channel: Channels::DIRECT,
        credit: 1.0
      )

      result = service.call
      totals = result[:data][:totals]

      # Should only count our account's 2.0 credits, not the other account's
      assert_equal 2.0, totals[:conversions]
    end

    private

    def service(date_range: "30d", models: nil, channels: Channels::ALL)
      models ||= [first_touch_model]
      filter_params = {
        date_range: date_range,
        models: models,
        channels: channels,
        journey_position: "last_touch",
        metric: "conversions"
      }
      Dashboard::ConversionsDataService.new(account, filter_params)
    end

    def account
      @account ||= accounts(:one)
    end

    def first_touch_model
      @first_touch_model ||= attribution_models(:first_touch)
    end

    def create_test_credits
      # Create conversion
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        revenue: 200,
        converted_at: 5.days.ago
      )

      # Create credits for different channels
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 1,
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        revenue_credit: 100,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 2,
        channel: Channels::EMAIL,
        credit: 0.5,
        revenue_credit: 50,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 3,
        channel: Channels::EMAIL,
        credit: 0.5,
        revenue_credit: 50,
        is_test: false
      )
    end

    def create_prior_period_credits
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        revenue: 100,
        converted_at: 35.days.ago
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 10,
        channel: Channels::DIRECT,
        credit: 1.0,
        revenue_credit: 100,
        is_test: false
      )
    end

    def create_credit_at(time)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: time
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: rand(100..999),
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        is_test: false
      )
    end

    def create_credit_for_model(model)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 5.days.ago
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: model,
        session_id: rand(100..999),
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        is_test: false
      )
    end

    def create_credit_with_campaign(channel, campaign_name)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 5.days.ago
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: rand(100..999),
        channel: channel,
        credit: 1.0,
        utm_campaign: campaign_name,
        is_test: false
      )
    end

    def create_credit(is_test: false)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 5.days.ago,
        is_test: is_test
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: rand(100..999),
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        is_test: is_test
      )
    end
  end

  # ==========================================
  # Caching tests
  # ==========================================

  class ConversionsCachingTest < ActiveSupport::TestCase
    setup do
      AttributionCredit.delete_all
      Conversion.where(account: account).delete_all
    end

    test "caches results on first call" do
      create_test_credits

      assert_difference -> { cache_writes }, 1 do
        service.call
      end
    end

    test "returns cached results on second call" do
      create_test_credits
      service.call

      assert_no_difference -> { cache_writes } do
        result = service.call
        assert_equal 2.0, result[:data][:totals][:conversions]
      end
    end

    test "cache is invalidated when attribution credit is created" do
      create_test_credits
      service.call # populate cache

      # Create new credit - should invalidate cache
      new_conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 3.days.ago
      )

      account.attribution_credits.create!(
        conversion: new_conversion,
        attribution_model: first_touch_model,
        session_id: rand(100..999),
        channel: Channels::DIRECT,
        credit: 1.0,
        is_test: false
      )

      # Next call should hit DB with new data
      result = service.call
      assert_equal 3.0, result[:data][:totals][:conversions]
    end

    test "different filter params use different cache keys" do
      create_test_credits

      service_7d = service(date_range: "7d")
      service_30d = service(date_range: "30d")

      # Both should cache separately
      assert_difference -> { cache_writes }, 2 do
        service_7d.call
        service_30d.call
      end
    end

    private

    def service(date_range: "30d", models: nil, channels: Channels::ALL)
      models ||= [first_touch_model]
      filter_params = {
        date_range: date_range,
        models: models,
        channels: channels,
        journey_position: "last_touch",
        metric: "conversions"
      }
      Dashboard::ConversionsDataService.new(account, filter_params)
    end

    def account
      @account ||= accounts(:one)
    end

    def first_touch_model
      @first_touch_model ||= attribution_models(:first_touch)
    end

    def cache_writes
      Rails.cache.instance_variable_get(:@data)&.size || 0
    end

    def create_test_credits
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        revenue: 200,
        converted_at: 5.days.ago
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 1,
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        revenue_credit: 100,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 2,
        channel: Channels::EMAIL,
        credit: 1.0,
        revenue_credit: 100,
        is_test: false
      )
    end
  end
end
