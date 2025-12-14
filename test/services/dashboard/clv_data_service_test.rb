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
      assert result[:data].present?
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
      assert_equal 147.0, totals[:clv]
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
      assert_equal 147.0, totals[:revenue]
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
      assert_equal 4.0, totals[:repurchase_frequency]
    end

    # ==========================================
    # By Channel Tests
    # ==========================================

    test "by_channel groups clv by acquisition channel" do
      create_multi_channel_clv_data
      result = service.call
      by_channel = result[:data][:by_channel]

      assert by_channel.is_a?(Array)
      channels = by_channel.map { |c| c[:channel] }
      assert_includes channels, Channels::ORGANIC_SEARCH
      assert_includes channels, Channels::PAID_SEARCH
    end

    test "by_channel calculates clv per channel" do
      create_multi_channel_clv_data
      result = service.call
      by_channel = result[:data][:by_channel]

      organic = by_channel.find { |c| c[:channel] == Channels::ORGANIC_SEARCH }
      assert organic[:clv].positive?
      assert organic[:customers].positive?
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

      assert coverage[:total].positive?
      assert coverage[:identified].positive?
      assert coverage[:percentage] > 0
      assert coverage[:percentage] <= 100
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

    test "filters customers by acquisition date not purchase date" do
      # Create an old customer acquired 60 days ago (outside 30d range)
      old_identity = account.identities.create!(
        external_id: "old_customer",
        first_identified_at: 60.days.ago,
        last_identified_at: Time.current
      )

      account.conversions.create!(
        visitor: visitors(:one),
        identity: old_identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 60.days.ago,
        is_test: false
      )

      # Recent payment from old customer (should NOT be included)
      account.conversions.create!(
        visitor: visitors(:one),
        identity: old_identity,
        conversion_type: "payment",
        revenue: 100,
        converted_at: 2.days.ago,
        is_test: false
      )

      # New customer acquired 10 days ago (within range)
      create_clv_test_data

      result = service.call
      totals = result[:data][:totals]

      # Only the new customer should be counted
      assert_equal 1, totals[:customers]
    end

    private

    def service
      @service ||= Dashboard::ClvDataService.new(account, filter_params)
    end

    def account
      @account ||= accounts(:one)
    end

    def filter_params
      {
        date_range: "30d",
        models: [attribution_models(:first_touch)],
        channels: Channels::ALL,
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
      [20.days.ago, 10.days.ago, 2.days.ago].each do |time|
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
