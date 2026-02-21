# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

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

      assert_empty conv.journey_session_ids

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

      assert_empty empty_conversion.journey_session_ids
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

    # ==========================================
    # Phase 2: Identity-aware attribution tests
    # ==========================================

    test "uses CrossDeviceCalculator when conversion has identity" do
      conv = build_cross_device_conversion
      result = build_service(conv).call

      assert result[:success]

      # Credits should span sessions from BOTH visitors
      credited_session_ids = conv.attribution_credits.pluck(:session_id).uniq
      visitor_ids = Session.where(id: credited_session_ids).pluck(:visitor_id).uniq

      assert_operator visitor_ids.size, :>, 1,
        "Cross-device attribution should credit sessions from multiple visitors"
    end

    test "falls back to single-visitor Calculator when no identity" do
      conv = build_conversion
      result = build_service(conv).call

      assert result[:success]

      # Credits should only come from the single visitor's sessions
      credited_session_ids = conv.attribution_credits.pluck(:session_id).uniq
      visitor_ids = Session.where(id: credited_session_ids).pluck(:visitor_id).uniq

      assert_equal [ conv.visitor_id ], visitor_ids,
        "Without identity, attribution should only use single visitor's sessions"
    end

    test "cross-device journey_session_ids includes sessions from multiple visitors" do
      conv = build_cross_device_conversion
      build_service(conv).call
      conv.reload

      visitor_ids = Session.where(id: conv.journey_session_ids).pluck(:visitor_id).uniq

      assert_operator visitor_ids.size, :>, 1,
        "Journey should span sessions from multiple identity-linked visitors"
    end

    # ==========================================
    # Phase 1: Attribution resilience tests
    # ==========================================

    test "isolates per-model failures and returns success" do
      shapley_model = create_shapley_model
      conv = build_conversion

      stub_exploding_shapley do
        result = build_service(conv).call

        assert result[:success],
          "Service should return success even when one model fails"
      end
    ensure
      shapley_model&.destroy!
    end

    test "persists credits from successful models when one model fails" do
      shapley_model = create_shapley_model
      conv = build_conversion

      stub_exploding_shapley do
        build_service(conv).call

        first_touch_credits = conv.attribution_credits
          .where(attribution_model: attribution_models(:first_touch))
        last_touch_credits = conv.attribution_credits
          .where(attribution_model: attribution_models(:last_touch))
        shapley_credits = conv.attribution_credits
          .where(attribution_model: shapley_model)

        assert_predicate first_touch_credits, :any?, "First Touch credits should be persisted"
        assert_predicate last_touch_credits, :any?, "Last Touch credits should be persisted"
        assert_empty shapley_credits, "Shapley credits should not exist (model failed)"
      end
    ensure
      shapley_model&.destroy!
    end

    test "populates journey_session_ids even when one model fails" do
      shapley_model = create_shapley_model
      conv = build_conversion

      stub_exploding_shapley do
        build_service(conv).call
        conv.reload

        assert_not_empty conv.journey_session_ids,
          "Journey should be stored even when one model fails"
      end
    ensure
      shapley_model&.destroy!
    end

    test "journey_session_ids contains all touchpoint sessions not just credited" do
      visitor = visitors(:two)
      create_multi_session_journey(visitor, count: 5)

      conv = Conversion.create!(
        account: visitor.account,
        visitor: visitor,
        conversion_type: "purchase",
        converted_at: Time.current,
        journey_session_ids: []
      )

      build_service(conv).call
      conv.reload

      assert_equal 5, conv.journey_session_ids.size,
        "Journey should contain all 5 touchpoint sessions, not just credited ones"
    end

    test "inherited attribution populates journey_session_ids" do
      acquisition_conversion = build_acquisition_conversion
      calculate_attribution(acquisition_conversion)

      payment_conversion = build_inheriting_conversion(acquisition_conversion)
      build_service(payment_conversion).call
      payment_conversion.reload

      assert_not_empty payment_conversion.journey_session_ids,
        "Inherited attribution should populate journey_session_ids"
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

    def account
      @account ||= accounts(:one)
    end

    def create_shapley_model
      AttributionModel.create!(
        account: account,
        name: "Shapley Test",
        model_type: :preset,
        algorithm: :shapley_value,
        is_active: true,
        lookback_days: 30
      )
    end

    def stub_exploding_shapley(&block)
      fake = ->(*_args, **_kwargs) {
        obj = Object.new
        obj.define_singleton_method(:call) { raise "O(2^n) power_set explosion" }
        obj
      }

      Attribution::Algorithms::ShapleyValue.stub(:new, fake, &block)
    end

    def build_cross_device_conversion
      identity = identities(:one)

      # Visitor A: desktop sessions
      visitor_a = visitors(:two)
      visitor_a.update!(identity: identity)
      Session.create!(
        account: visitor_a.account,
        visitor: visitor_a,
        session_id: SecureRandom.hex(16),
        started_at: 10.days.ago,
        channel: "organic_search",
        initial_utm: { "utm_source" => "google" }
      )

      # Visitor B: mobile sessions (same identity, different device)
      visitor_b = account.visitors.create!(
        visitor_id: "vis_mobile_#{SecureRandom.hex(8)}",
        identity: identity,
        first_seen_at: 7.days.ago,
        last_seen_at: 2.days.ago
      )
      Session.create!(
        account: account,
        visitor: visitor_b,
        session_id: SecureRandom.hex(16),
        started_at: 5.days.ago,
        channel: "paid_search",
        initial_utm: { "utm_source" => "facebook" }
      )

      Conversion.create!(
        account: account,
        visitor: visitor_a,
        identity: identity,
        conversion_type: "purchase",
        revenue: 100.00,
        converted_at: Time.current,
        journey_session_ids: []
      )
    end

    def create_multi_session_journey(visitor, count:)
      channels = %w[organic_search email paid_search social direct]

      count.times.map do |i|
        Session.create!(
          account: visitor.account,
          visitor: visitor,
          session_id: SecureRandom.hex(16),
          started_at: (count - i).days.ago,
          channel: channels[i % channels.size],
          initial_utm: { "utm_source" => "source_#{i}" }
        )
      end
    end
  end
end
