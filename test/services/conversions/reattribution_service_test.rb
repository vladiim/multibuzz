# frozen_string_literal: true

require "test_helper"

module Conversions
  class ReattributionServiceTest < ActiveSupport::TestCase
    test "successfully reattributes conversion with identity" do
      result = service.call

      assert result[:success], "Expected success but got: #{result[:errors]&.join(', ')}"
      assert result[:credits_by_model].present?
    end

    test "deletes existing credits before recalculating" do
      # First calculate initial attribution
      initial_result = Conversions::AttributionCalculationService.new(conversion).call
      assert initial_result[:success]

      initial_credits = conversion.attribution_credits.count
      assert initial_credits.positive?

      # Now reattribute - should delete and recalculate
      result = service.call

      assert result[:success]
      # Credits should be replaced, not added
      assert_equal initial_credits, conversion.attribution_credits.reload.count
    end

    test "returns error when conversion has no identity" do
      no_identity_conversion = build_conversion_without_identity

      result = Conversions::ReattributionService.new(no_identity_conversion).call

      refute result[:success]
      assert_includes result[:errors], "Conversion has no identity"
    end

    test "calculates credits for all active attribution models" do
      result = service.call

      assert result[:success]
      assert_includes result[:credits_by_model].keys, "First Touch"
      assert_includes result[:credits_by_model].keys, "Last Touch"
    end

    private

    def service
      @service ||= Conversions::ReattributionService.new(conversion)
    end

    def conversion
      @conversion ||= build_conversion
    end

    def build_conversion
      visitor = visitors(:two)
      identity = identities(:one)

      create_sessions_for_visitor(visitor)
      visitor.update!(identity: identity)

      Conversion.create!(
        account: visitor.account,
        visitor: visitor,
        identity: identity,
        conversion_type: "purchase",
        revenue: 100.00,
        converted_at: Time.current,
        journey_session_ids: []
      )
    end

    def build_conversion_without_identity
      visitor = visitors(:two)
      visitor.update!(identity: nil)

      Conversion.create!(
        account: visitor.account,
        visitor: visitor,
        identity: nil,
        conversion_type: "purchase",
        revenue: 50.00,
        converted_at: Time.current,
        journey_session_ids: []
      )
    end

    def create_sessions_for_visitor(visitor)
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
        channel: "paid_search",
        initial_utm: { "utm_source" => "google", "utm_medium" => "cpc" }
      )
    end
  end
end
