# frozen_string_literal: true

require "test_helper"

module Conversions
  class ReattributionServiceTest < ActiveSupport::TestCase
    test "successfully reattributes conversion with identity" do
      result = service.call

      assert result[:success], "Expected success but got: #{result[:errors]&.join(', ')}"
      assert_predicate result[:credits_by_model], :present?
    end

    test "deletes existing credits before recalculating" do
      # First calculate initial attribution
      initial_result = Conversions::AttributionCalculationService.new(conversion).call

      assert initial_result[:success]

      initial_credits = conversion.attribution_credits.count

      assert_predicate initial_credits, :positive?

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

    test "double reattribution produces same credit count not duplicates" do
      first_result = service.call

      assert first_result[:success]

      credits_after_first = conversion.attribution_credits.reload.count

      second_result = Conversions::ReattributionService.new(conversion).call

      assert second_result[:success]

      credits_after_second = conversion.attribution_credits.reload.count

      assert_equal credits_after_first, credits_after_second,
        "Second reattribution should replace, not duplicate credits"
    end

    test "invalidates dashboard cache exactly once per call (one batched invalidation, not per credit)" do
      Conversions::AttributionCalculationService.new(conversion).call

      assert_predicate conversion.attribution_credits.reload.count, :positive?

      Dashboard::CacheInvalidator.delete_matched_supported? # warm the probe so it does not count
      counting_cache.reset_counters!

      service.call

      assert_equal Dashboard::CacheInvalidator::SECTIONS.size, counting_cache.delete_matched_count,
        "Expected exactly one delete_matched per section (one batched CacheInvalidator#call), got #{counting_cache.delete_matched_count}"
    end

    test "AttributionCredit after_commit invalidation still fires for writes outside the service" do
      Dashboard::CacheInvalidator.delete_matched_supported? # warm the probe so it does not count
      counting_cache.reset_counters!

      AttributionCredit.create!(
        account: conversion.account,
        conversion: conversion,
        attribution_model: attribution_models(:first_touch),
        session_id: SecureRandom.hex(16),
        channel: "organic_search",
        credit: 1.0,
        revenue_credit: 100.00
      )

      assert_equal Dashboard::CacheInvalidator::SECTIONS.size, counting_cache.delete_matched_count,
        "Direct AttributionCredit.create! outside the service should trigger one CacheInvalidator (got #{counting_cache.delete_matched_count})"
    end

    private

    setup do
      @original_cache = Rails.cache
      Rails.cache = counting_cache
      Dashboard::CacheInvalidator.reset_delete_matched_support!
    end

    teardown do
      Rails.cache = @original_cache if @original_cache
      Dashboard::CacheInvalidator.reset_delete_matched_support!
    end

    def counting_cache = @counting_cache ||= CountingCacheStore.new

    class CountingCacheStore < ActiveSupport::Cache::MemoryStore
      attr_reader :delete_matched_count

      def initialize(*)
        super
        @delete_matched_count = 0
      end

      def reset_counters!
        @delete_matched_count = 0
      end

      def delete_matched(*)
        @delete_matched_count += 1
        super
      end
    end

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
