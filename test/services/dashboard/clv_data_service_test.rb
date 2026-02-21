# frozen_string_literal: true

require "test_helper"

module Dashboard
  class ClvDataServiceTest < ActiveSupport::TestCase
    setup do
      AttributionCredit.delete_all
      Conversion.where(account: account).delete_all
    end

    # ==========================================
    # Service Structure Tests
    # ==========================================

    test "returns success result" do
      result = service.call

      assert result[:success]
      assert_predicate result[:data], :present?
    end

    test "returns all required data keys" do
      result = service.call

      assert result[:data].key?(:totals)
      assert result[:data].key?(:by_channel)
      assert result[:data].key?(:smiling_curve)
      assert result[:data].key?(:cohort_analysis)
      assert result[:data].key?(:coverage)
    end

    # ==========================================
    # Totals Tests
    # ==========================================

    test "totals include all required metrics" do
      create_clv_test_data
      result = service.call
      totals = result[:data][:totals]

      assert totals.key?(:clv)
      assert totals.key?(:customers)
      assert totals.key?(:purchases)
      assert totals.key?(:revenue)
      assert totals.key?(:avg_duration)
      assert totals.key?(:repurchase_frequency)
    end

    test "clv is calculated as total revenue divided by customers" do
      create_clv_test_data
      result = service.call
      totals = result[:data][:totals]

      # 1 customer, 3 payments of $49 = $147 total
      assert_in_delta(147.0, totals[:clv])
    end

    test "customers counts distinct identities with is_acquisition in date range" do
      create_clv_test_data
      result = service.call
      totals = result[:data][:totals]

      assert_equal 1, totals[:customers]
    end

    test "purchases counts all conversions for acquired customers" do
      create_clv_test_data
      result = service.call
      totals = result[:data][:totals]

      # 1 acquisition + 3 payments = 4 conversions
      assert_equal 4, totals[:purchases]
    end

    test "revenue sums all revenue for acquired customers" do
      create_clv_test_data
      result = service.call
      totals = result[:data][:totals]

      # 3 payments * $49 = $147
      assert_in_delta(147.0, totals[:revenue])
    end

    test "avg_duration calculates average customer lifespan in days" do
      create_clv_test_data
      result = service.call
      totals = result[:data][:totals]

      # From acquisition (20 days ago) to last payment (2 days ago) = 18 days
      assert_equal 18, totals[:avg_duration]
    end

    test "repurchase_frequency calculates purchases per customer" do
      create_clv_test_data
      result = service.call
      totals = result[:data][:totals]

      # 4 conversions / 1 customer = 4.0
      assert_in_delta(4.0, totals[:repurchase_frequency])
    end

    # ==========================================
    # By Channel Tests
    # ==========================================

    test "by_channel groups clv by acquisition channel" do
      create_multi_channel_clv_data
      result = service.call
      by_channel = result[:data][:by_channel]

      assert_kind_of Array, by_channel
      channels = by_channel.map { |c| c[:channel] }

      assert_includes channels, Channels::ORGANIC_SEARCH
      assert_includes channels, Channels::PAID_SEARCH
    end

    test "by_channel calculates clv per channel" do
      create_multi_channel_clv_data
      result = service.call
      by_channel = result[:data][:by_channel]

      organic = by_channel.find { |c| c[:channel] == Channels::ORGANIC_SEARCH }

      assert_predicate organic[:clv], :positive?
      assert_predicate organic[:customers], :positive?
    end

    # ==========================================
    # Coverage Tests
    # ==========================================

    test "coverage calculates percentage of identified conversions" do
      create_clv_test_data
      # Add an anonymous conversion
      account.conversions.create!(
        visitor: visitors(:one),
        identity: nil,
        conversion_type: "anon_purchase",
        converted_at: 5.days.ago,
        is_test: false
      )

      result = service.call
      coverage = result[:data][:coverage]

      assert_predicate coverage[:total], :positive?
      assert_predicate coverage[:identified], :positive?
      assert_operator coverage[:percentage], :>, 0
      assert_operator coverage[:percentage], :<=, 100
    end

    # ==========================================
    # Empty State Tests
    # ==========================================

    test "returns empty totals when no acquisition data" do
      result = service.call
      totals = result[:data][:totals]

      assert_equal 0, totals[:customers]
      assert_equal 0, totals[:clv]
    end

    test "has_data is false when no acquisitions" do
      result = service.call

      assert_not result[:data][:has_data]
    end

    test "has_data is true when acquisitions exist" do
      create_clv_test_data
      result = service.call

      assert result[:data][:has_data]
    end

    # ==========================================
    # Date Range Filtering Tests
    # ==========================================

    test "date range filter limits acquisition cohort" do
      # Customer acquired 40 days ago (outside 30d range)
      old_identity = account.identities.create!(
        external_id: "old_customer",
        first_identified_at: 40.days.ago,
        last_identified_at: Time.current
      )

      account.conversions.create!(
        visitor: visitors(:one),
        identity: old_identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 40.days.ago,
        is_test: false
      )

      # Customer acquired 10 days ago (inside 30d range)
      recent_identity = account.identities.create!(
        external_id: "recent_customer",
        first_identified_at: 10.days.ago,
        last_identified_at: Time.current
      )

      account.conversions.create!(
        visitor: visitors(:one),
        identity: recent_identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 10.days.ago,
        is_test: false
      )

      result = service.call
      totals = result[:data][:totals]

      # Only the customer acquired in the last 30 days should be included
      assert_equal 1, totals[:customers]
    end

    # ==========================================
    # Channel Filtering Tests
    # ==========================================

    test "channel filter limits acquisitions by acquisition channel" do
      # Customer acquired via organic search
      organic_identity = account.identities.create!(
        external_id: "organic_customer",
        first_identified_at: 10.days.ago,
        last_identified_at: Time.current
      )

      organic_acquisition = account.conversions.create!(
        visitor: visitors(:one),
        identity: organic_identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 10.days.ago,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: organic_acquisition,
        attribution_model: first_touch_model,
        session_id: rand(1000..9999),
        channel: Channels::ORGANIC_SEARCH,
        credit: 1.0,
        is_test: false
      )

      # Customer acquired via paid search
      paid_identity = account.identities.create!(
        external_id: "paid_customer",
        first_identified_at: 10.days.ago,
        last_identified_at: Time.current
      )

      paid_acquisition = account.conversions.create!(
        visitor: visitors(:one),
        identity: paid_identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 10.days.ago,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: paid_acquisition,
        attribution_model: first_touch_model,
        session_id: rand(1000..9999),
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        is_test: false
      )

      # Filter to only organic search
      result = service_with_channels([ Channels::ORGANIC_SEARCH ]).call
      totals = result[:data][:totals]

      assert_equal 1, totals[:customers]
    end

    # ==========================================
    # Conversion Filter Tests
    # ==========================================

    test "conversion filters limit acquisitions by conversion properties" do
      # Customer with signup acquisition
      signup_identity = account.identities.create!(
        external_id: "signup_customer",
        first_identified_at: 10.days.ago,
        last_identified_at: Time.current
      )

      account.conversions.create!(
        visitor: visitors(:one),
        identity: signup_identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 10.days.ago,
        is_test: false
      )

      # Customer with trial_start acquisition
      trial_identity = account.identities.create!(
        external_id: "trial_customer",
        first_identified_at: 10.days.ago,
        last_identified_at: Time.current
      )

      account.conversions.create!(
        visitor: visitors(:one),
        identity: trial_identity,
        conversion_type: "trial_start",
        is_acquisition: true,
        converted_at: 10.days.ago,
        is_test: false
      )

      # Filter to only signup conversions
      conversion_filters = [
        { field: "conversion_type", operator: "equals", values: [ "signup" ] }
      ]
      result = service_with_conversion_filters(conversion_filters).call
      totals = result[:data][:totals]

      assert_equal 1, totals[:customers]
    end

    test "all filters combine correctly" do
      # Customer 1: Inside date range, organic, signup (MATCHES ALL)
      match_identity = account.identities.create!(
        external_id: "matching_customer",
        first_identified_at: 10.days.ago,
        last_identified_at: Time.current
      )

      match_acquisition = account.conversions.create!(
        visitor: visitors(:one),
        identity: match_identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 10.days.ago,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: match_acquisition,
        attribution_model: first_touch_model,
        session_id: rand(1000..9999),
        channel: Channels::ORGANIC_SEARCH,
        credit: 1.0,
        is_test: false
      )

      # Customer 2: Inside date range, paid search, signup
      paid_identity = account.identities.create!(
        external_id: "paid_customer",
        first_identified_at: 10.days.ago,
        last_identified_at: Time.current
      )

      paid_acquisition = account.conversions.create!(
        visitor: visitors(:one),
        identity: paid_identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 10.days.ago,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: paid_acquisition,
        attribution_model: first_touch_model,
        session_id: rand(1000..9999),
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        is_test: false
      )

      # Customer 3: Outside date range, organic, signup
      old_identity = account.identities.create!(
        external_id: "old_customer",
        first_identified_at: 40.days.ago,
        last_identified_at: Time.current
      )

      old_acquisition = account.conversions.create!(
        visitor: visitors(:one),
        identity: old_identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 40.days.ago,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: old_acquisition,
        attribution_model: first_touch_model,
        session_id: rand(1000..9999),
        channel: Channels::ORGANIC_SEARCH,
        credit: 1.0,
        is_test: false
      )

      # Apply date (30d) + channel (organic) filters
      result = service_with_channels([ Channels::ORGANIC_SEARCH ]).call
      totals = result[:data][:totals]

      # Only customer 1 should match both filters
      assert_equal 1, totals[:customers]
    end

    test "includes full lifetime revenue for customers acquired in date range" do
      # Create customer acquired within date range (10 days ago)
      recent_identity = account.identities.create!(
        external_id: "recent_customer",
        first_identified_at: 10.days.ago,
        last_identified_at: Time.current
      )

      account.conversions.create!(
        visitor: visitors(:one),
        identity: recent_identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 10.days.ago,
        is_test: false
      )

      # Payment from this customer (within range)
      account.conversions.create!(
        visitor: visitors(:one),
        identity: recent_identity,
        conversion_type: "payment",
        revenue: 100,
        converted_at: 5.days.ago,
        is_test: false
      )

      # Payment from this customer (recent - still included as it's lifetime value)
      account.conversions.create!(
        visitor: visitors(:one),
        identity: recent_identity,
        conversion_type: "payment",
        revenue: 50,
        converted_at: 2.days.ago,
        is_test: false
      )

      result = service.call
      totals = result[:data][:totals]

      # 1 customer acquired in range
      assert_equal 1, totals[:customers]
      # Full lifetime revenue: $100 + $50 = $150
      assert_in_delta(150.0, totals[:revenue])
    end

    private

    def service
      @service ||= Dashboard::ClvDataService.new(account, filter_params)
    end

    def service_with_channels(channels)
      Dashboard::ClvDataService.new(account, filter_params.merge(channels: channels))
    end

    def service_with_conversion_filters(conversion_filters)
      Dashboard::ClvDataService.new(account, filter_params.merge(conversion_filters: conversion_filters))
    end

    def account
      @account ||= accounts(:one)
    end

    def filter_params
      {
        date_range: "30d",
        models: [ attribution_models(:first_touch) ],
        channels: Channels::ALL,
        conversion_filters: [],
        test_mode: false
      }
    end

    def identity
      @identity ||= account.identities.create!(
        external_id: "clv_test_user",
        first_identified_at: 30.days.ago,
        last_identified_at: Time.current
      )
    end

    def first_touch_model
      @first_touch_model ||= attribution_models(:first_touch)
    end

    def create_clv_test_data
      # Create acquisition conversion (20 days ago - within 30d range)
      acquisition = account.conversions.create!(
        visitor: visitors(:one),
        identity: identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 20.days.ago,
        is_test: false
      )

      # Create acquisition attribution
      account.attribution_credits.create!(
        conversion: acquisition,
        attribution_model: first_touch_model,
        session_id: 1,
        channel: Channels::ORGANIC_SEARCH,
        credit: 1.0,
        revenue_credit: 0,
        is_test: false
      )

      # Create subsequent payments
      [ 20.days.ago, 10.days.ago, 2.days.ago ].each do |time|
        payment = account.conversions.create!(
          visitor: visitors(:one),
          identity: identity,
          conversion_type: "payment",
          revenue: 49.00,
          converted_at: time,
          is_test: false
        )

        account.attribution_credits.create!(
          conversion: payment,
          attribution_model: first_touch_model,
          session_id: 1,
          channel: Channels::ORGANIC_SEARCH,
          credit: 1.0,
          revenue_credit: 49.00,
          is_test: false
        )
      end
    end

    def create_multi_channel_clv_data
      create_clv_test_data

      # Create second customer from paid search
      paid_identity = account.identities.create!(
        external_id: "paid_customer",
        first_identified_at: 20.days.ago,
        last_identified_at: Time.current
      )

      acquisition = account.conversions.create!(
        visitor: visitors(:one),
        identity: paid_identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 20.days.ago,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: acquisition,
        attribution_model: first_touch_model,
        session_id: 2,
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        revenue_credit: 0,
        is_test: false
      )

      # One payment for paid customer
      payment = account.conversions.create!(
        visitor: visitors(:one),
        identity: paid_identity,
        conversion_type: "payment",
        revenue: 99.00,
        converted_at: 5.days.ago,
        is_test: false
      )

      account.attribution_credits.create!(
        conversion: payment,
        attribution_model: first_touch_model,
        session_id: 2,
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        revenue_credit: 99.00,
        is_test: false
      )
    end
  end
end
