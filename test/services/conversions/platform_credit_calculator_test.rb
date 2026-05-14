# frozen_string_literal: true

require "test_helper"

module Conversions
  class PlatformCreditCalculatorTest < ActiveSupport::TestCase
    test "returns full credit when only touchpoint is from the destination's platform" do
      meta_session = create_session(click_ids: { "fbclid" => "AbC" })
      conversion = create_conversion_with_credits(model: model, credits: { meta_session => 1.0 })

      assert_in_delta 1.0, PlatformCreditCalculator.new(conversion, meta_destination).call
    end

    test "returns zero when no touchpoint matches the destination's platform" do
      organic_session = create_session(click_ids: {})
      conversion = create_conversion_with_credits(model: model, credits: { organic_session => 1.0 })

      assert_in_delta 0.0, PlatformCreditCalculator.new(conversion, meta_destination).call
    end

    test "linear model with mixed touchpoints returns the meta share" do
      meta_session = create_session(click_ids: { "fbclid" => "M1" })
      google_session = create_session(click_ids: { "gclid" => "G1" })
      organic_session = create_session(click_ids: {})
      conversion = create_conversion_with_credits(
        model: model,
        credits: { meta_session => 0.34, google_session => 0.33, organic_session => 0.33 }
      )

      assert_in_delta 0.34, PlatformCreditCalculator.new(conversion, meta_destination).call, 0.01
    end

    test "returns zero when conversion has no attribution credits" do
      conversion = create_conversion

      assert_in_delta 0.0, PlatformCreditCalculator.new(conversion, meta_destination).call
    end

    test "ignores credits for other attribution models" do
      meta_session = create_session(click_ids: { "fbclid" => "AbC" })
      conversion = create_conversion_with_credits(model: attribution_models(:first_touch), credits: { meta_session => 1.0 })

      assert_in_delta 0.0, PlatformCreditCalculator.new(conversion, meta_destination).call
    end

    private

    def account = @account ||= accounts(:one)
    def visitor = @visitor ||= visitors(:one)

    def model
      @model ||= attribution_models(:linear)
    end

    def meta_destination
      @meta_destination ||= ConversionDestination.create!(
        account: account, attribution_model: model, platform: "meta_capi", name: "Test Meta",
        meta_pixel_id: "P", meta_access_token: "T", enabled: true
      )
    end

    def create_session(click_ids:)
      account.sessions.create!(
        session_id: "sess_#{SecureRandom.hex(6)}", visitor: visitor,
        started_at: 1.hour.ago, last_activity_at: 1.hour.ago, click_ids: click_ids
      )
    end

    def create_conversion(extras = {})
      account.conversions.create!(
        { visitor: visitor, conversion_type: "Lead", converted_at: Time.current,
          idempotency_key: "calc_#{SecureRandom.hex(4)}" }.merge(extras)
      )
    end

    def create_conversion_with_credits(model:, credits:)
      conversion = create_conversion
      credits.each do |session, credit|
        AttributionCredit.create!(
          account: account, conversion: conversion, attribution_model: model,
          session_id: session.id, channel: "paid_social", credit: credit
        )
      end
      conversion
    end
  end
end
