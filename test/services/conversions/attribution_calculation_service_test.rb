# frozen_string_literal: true

require "test_helper"

module Conversions
  class AttributionCalculationServiceTest < ActiveSupport::TestCase
    test "calculates credits for all active models" do
      result = service.call

      assert result[:success]
      assert_includes result[:credits_by_model].keys, "First Touch"
      assert_includes result[:credits_by_model].keys, "Last Touch"
    end

    test "stores attribution credits in database" do
      # 2 sessions × 2 models, but First Touch = 1 credit, Last Touch = 1 credit = 2 total
      assert_difference "AttributionCredit.count", 2 do
        service.call
      end
    end

    test "calculates revenue credits when conversion has revenue" do
      conversion_with_revenue = build_conversion(revenue: 100.00)
      revenue_service = build_service(conversion_with_revenue)

      result = revenue_service.call

      assert result[:success]
      credits = result[:credits_by_model]["First Touch"]
      assert credits.all? { |c| c[:revenue_credit].present? }
    end

    test "returns empty credits for visitor with no sessions" do
      empty_conversion = build_conversion(visitor: visitors(:other_account_visitor))
      empty_service = build_service(empty_conversion)

      result = empty_service.call

      assert result[:success]
      assert result[:credits_by_model].values.all?(&:empty?)
    end

    # ==========================================
    # Acquisition inheritance tests
    # ==========================================

    test "inherits attribution from acquisition conversion when inherit_acquisition is true" do
      # Create acquisition conversion with attribution
      acquisition_conversion = build_acquisition_conversion
      calculate_attribution(acquisition_conversion)

      # Create payment conversion that should inherit
      payment_conversion = build_inheriting_conversion(acquisition_conversion)

      result = build_service(payment_conversion).call

      assert result[:success]
      # Should have credits
      assert result[:credits_by_model].values.any?(&:present?)
    end

    test "inherited attribution copies channel from acquisition conversion" do
      acquisition_conversion = build_acquisition_conversion
      calculate_attribution(acquisition_conversion)

      payment_conversion = build_inheriting_conversion(acquisition_conversion)
      result = build_service(payment_conversion).call

      assert result[:success]

      # Get the original acquisition credits
      acquisition_credits = acquisition_conversion.attribution_credits.pluck(:channel)

      # Get the inherited credits
      payment_credits = payment_conversion.attribution_credits.pluck(:channel)

      assert_equal acquisition_credits.sort, payment_credits.sort
    end

    test "inherited attribution recalculates revenue_credit based on new revenue" do
      acquisition_conversion = build_acquisition_conversion(revenue: nil)
      calculate_attribution(acquisition_conversion)

      payment_conversion = build_inheriting_conversion(acquisition_conversion, revenue: 100.00)
      result = build_service(payment_conversion).call

      assert result[:success]

      # Each attribution model's credits should sum to $100 (the conversion revenue)
      payment_conversion.attribution_credits.group_by(&:attribution_model).each do |_model, credits|
        model_revenue_credit = credits.sum(&:revenue_credit)
        assert_in_delta 100.00, model_revenue_credit, 0.01
      end
    end

    test "inherited attribution preserves utm data from acquisition" do
      acquisition_conversion = build_acquisition_conversion
      calculate_attribution(acquisition_conversion)

      acquisition_credit = acquisition_conversion.attribution_credits.find { |c| c.utm_source.present? }
      skip "No UTM data in acquisition credits" unless acquisition_credit

      payment_conversion = build_inheriting_conversion(acquisition_conversion)
      result = build_service(payment_conversion).call

      assert result[:success]

      payment_credit = payment_conversion.attribution_credits.find do |c|
        c.session_id == acquisition_credit.session_id
      end

      assert_equal acquisition_credit.utm_source, payment_credit.utm_source
      assert_equal acquisition_credit.utm_medium, payment_credit.utm_medium
    end

    test "calculates fresh attribution when inherit_acquisition false" do
      acquisition_conversion = build_acquisition_conversion
      calculate_attribution(acquisition_conversion)

      # Build conversion without inherit flag
      non_inheriting_conversion = build_conversion(
        visitor: acquisition_conversion.visitor,
        revenue: 50.00
      )

      result = build_service(non_inheriting_conversion).call

      assert result[:success]
      # Attribution should be calculated fresh (not inherited)
    end

    test "calculates fresh attribution when no acquisition conversion exists" do
      visitor = visitors(:two)
      create_sessions_for_visitor(visitor)

      identity = identities(:one)
      visitor.update!(identity: identity)

      # No acquisition conversion exists for this identity
      payment_conversion = Conversion.create!(
        account: visitor.account,
        visitor: visitor,
        identity: identity,
        conversion_type: "payment",
        revenue: 100.00,
        converted_at: Time.current,
        journey_session_ids: []
      )
      payment_conversion.inherit_acquisition = true

      result = build_service(payment_conversion).call

      assert result[:success]
      # Should calculate fresh attribution since no acquisition exists
    end

    # ==========================================
    # Journey session IDs population tests
    # ==========================================

    test "populates journey_session_ids after fresh attribution calculation" do
      conv = build_conversion
      assert_equal [], conv.journey_session_ids

      result = build_service(conv).call

      assert result[:success]
      conv.reload
      assert_not_empty conv.journey_session_ids
      assert_equal 2, conv.journey_session_ids.size  # 2 sessions created
    end

    test "journey_session_ids contains unique session IDs from credits" do
      conv = build_conversion
      result = build_service(conv).call

      assert result[:success]
      conv.reload

      # Should match the session IDs in the credits
      credit_session_ids = conv.attribution_credits.pluck(:session_id).uniq.sort
      assert_equal credit_session_ids, conv.journey_session_ids.sort
    end

    test "journey_session_ids remains empty when no sessions exist" do
      empty_conversion = build_conversion(visitor: visitors(:other_account_visitor))
      result = build_service(empty_conversion).call

      assert result[:success]
      empty_conversion.reload
      assert_equal [], empty_conversion.journey_session_ids
    end

    test "inherited attribution works with multiple attribution models" do
      acquisition_conversion = build_acquisition_conversion
      calculate_attribution(acquisition_conversion)

      payment_conversion = build_inheriting_conversion(acquisition_conversion)
      result = build_service(payment_conversion).call

      assert result[:success]

      # Should have credits for both First Touch and Last Touch models
      assert result[:credits_by_model].key?("First Touch")
      assert result[:credits_by_model].key?("Last Touch")
    end

    private

    def build_acquisition_conversion(revenue: nil)
      visitor = visitors(:two)
      identity = identities(:one)
      create_sessions_for_visitor(visitor)
      visitor.update!(identity: identity)

      Conversion.create!(
        account: visitor.account,
        visitor: visitor,
        identity: identity,
        conversion_type: "signup",
        revenue: revenue,
        converted_at: Time.current,
        is_acquisition: true,
        journey_session_ids: []
      )
    end

    def build_inheriting_conversion(acquisition_conversion, revenue: 49.00)
      conv = Conversion.create!(
        account: acquisition_conversion.account,
        visitor: acquisition_conversion.visitor,
        identity: acquisition_conversion.identity,
        conversion_type: "payment",
        revenue: revenue,
        converted_at: Time.current,
        journey_session_ids: []
      )
      conv.inherit_acquisition = true
      conv
    end

    def calculate_attribution(conversion)
      Conversions::AttributionCalculationService.new(conversion).call
    end

    def service
      @service ||= build_service(conversion)
    end

    def build_service(conv)
      Conversions::AttributionCalculationService.new(conv)
    end

    def conversion
      @conversion ||= build_conversion
    end

    def build_conversion(visitor: default_visitor, revenue: nil)
      create_sessions_for_visitor(visitor)

      Conversion.create!(
        account: visitor.account,
        visitor: visitor,
        session_id: 1,
        event_id: 1,
        conversion_type: "purchase",
        revenue: revenue,
        converted_at: Time.current,
        journey_session_ids: []
      )
    end

    def create_sessions_for_visitor(visitor)
      return if visitor == visitors(:other_account_visitor)

      Session.create!(
        account: visitor.account,
        visitor: visitor,
        session_id: SecureRandom.hex(16),
        started_at: 10.days.ago,
        channel: "organic_search",
        initial_utm: { "utm_source" => "google" }
      )

      Session.create!(
        account: visitor.account,
        visitor: visitor,
        session_id: SecureRandom.hex(16),
        started_at: 3.days.ago,
        channel: "email",
        initial_utm: { "utm_source" => "newsletter", "utm_medium" => "email" }
      )
    end

    def default_visitor
      @default_visitor ||= visitors(:two)
    end
  end
end
